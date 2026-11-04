import Foundation

struct UsageBucket: Codable, Equatable {
    var down: UInt64 = 0
    var up: UInt64 = 0

    var total: UInt64 { down &+ up }

    mutating func add(down downBytes: UInt64, up upBytes: UInt64) {
        down &+= downBytes
        up &+= upBytes
    }

    mutating func merge(_ other: UsageBucket) {
        down &+= other.down
        up &+= other.up
    }
}

struct QuotaRecord: Codable, Equatable {
    var limitBytes: UInt64
    var consumedBytes: UInt64
    var startedAt: Date
    var isExhausted: Bool

    var remaining: UInt64 {
        limitBytes > consumedBytes ? limitBytes - consumedBytes : 0
    }

    var progress: Double {
        guard limitBytes > 0 else { return 1 }
        return min(1, max(0, Double(consumedBytes) / Double(limitBytes)))
    }
}

struct UsageSnapshot: Equatable {
    var today = UsageBucket()
    var week = UsageBucket()
    var month = UsageBucket()

    static let zero = UsageSnapshot()
}

/// 本机流量账本：按天累计下载 / 上传字节，并保存倒计时状态。
@MainActor
final class UsageStore {
    enum ResetScope: String, Identifiable {
        case today, week, month, all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "今日"
            case .week: return "本周"
            case .month: return "本月"
            case .all: return "全部"
            }
        }
    }

    static let shared = UsageStore()

    let storageURL: URL

    private var file = UsageFile()
    private var dirty = false
    private var lastSavedAt = Date.distantPast
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        storageURL = Self.defaultStorageURL()
        load()
    }

    // MARK: - Quota

    var quota: QuotaRecord? {
        get { file.quota }
        set {
            file.quota = newValue
            dirty = true
        }
    }

    // MARK: - Recording

    func addTraffic(down: UInt64, up: UInt64, at date: Date) {
        guard down > 0 || up > 0 else { return }
        let key = Self.dayKey(for: date)
        var bucket = file.days[key] ?? UsageBucket()
        bucket.add(down: down, up: up)
        file.days[key] = bucket
        dirty = true
    }

    func snapshot(now: Date = Date()) -> UsageSnapshot {
        let calendar = Calendar.current
        let todayKey = Self.dayKey(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let month = calendar.dateInterval(of: .month, for: now)

        var result = UsageSnapshot()
        for (key, bucket) in file.days {
            if key == todayKey {
                result.today.merge(bucket)
            }
            guard let date = Self.date(fromDayKey: key) else { continue }
            if let week, week.contains(date) {
                result.week.merge(bucket)
            }
            if let month, month.contains(date) {
                result.month.merge(bucket)
            }
        }
        return result
    }

    // MARK: - Reset

    func reset(_ scope: ResetScope, now: Date = Date()) {
        let calendar = Calendar.current
        switch scope {
        case .today:
            file.days.removeValue(forKey: Self.dayKey(for: now))
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                file.days = file.days.filter { key, _ in
                    guard let date = Self.date(fromDayKey: key) else { return false }
                    return !interval.contains(date)
                }
            }
        case .month:
            if let interval = calendar.dateInterval(of: .month, for: now) {
                file.days = file.days.filter { key, _ in
                    guard let date = Self.date(fromDayKey: key) else { return false }
                    return !interval.contains(date)
                }
            }
        case .all:
            file.days.removeAll()
        }
        dirty = true
        save(force: true)
    }

    // MARK: - Persistence

    func save(force: Bool = false) {
        guard dirty else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSavedAt) >= 5 else { return }
        prune(now: now)
        file.savedAt = now
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(file)
            try data.write(to: storageURL, options: [.atomic])
            dirty = false
            lastSavedAt = now
        } catch {
            print("[TrafficSentinel] 保存流量数据失败：\(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            file = try decoder.decode(UsageFile.self, from: data)
        } catch {
            let backupName = "usage-corrupt-\(Int(Date().timeIntervalSince1970)).json"
            let backupURL = storageURL.deletingLastPathComponent().appendingPathComponent(backupName)
            try? FileManager.default.moveItem(at: storageURL, to: backupURL)
            print("[TrafficSentinel] 流量数据损坏，已备份到 \(backupURL.lastPathComponent)：\(error)")
        }
    }

    private func prune(now: Date) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: now) else { return }
        let cutoffKey = Self.dayKey(for: cutoff)
        file.days = file.days.filter { $0.key >= cutoffKey }
    }

    // MARK: - Date keys

    static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components)
    }

    private static func defaultStorageURL() -> URL {
        // 测试或便携使用时可通过环境变量把账本放到指定目录。
        if let custom = ProcessInfo.processInfo.environment["TRAFFIC_SENTINEL_SUPPORT_DIR"],
           custom.isEmpty == false {
            return URL(fileURLWithPath: custom, isDirectory: true)
                .appendingPathComponent("usage.json")
        }

        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("TrafficSentinel", isDirectory: true)
            .appendingPathComponent("usage.json")
    }
}

private struct UsageFile: Codable {
    var version = 1
    var days: [String: UsageBucket] = [:]
    var quota: QuotaRecord?
    var savedAt: Date?
}
