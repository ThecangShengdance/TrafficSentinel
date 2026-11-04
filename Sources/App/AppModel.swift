import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var downloadSpeed: Double = 0
    @Published private(set) var uploadSpeed: Double = 0
    @Published private(set) var snapshot: UsageSnapshot = .zero
    @Published private(set) var quota: QuotaRecord?
    @Published private(set) var history: [SpeedSample] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastQuotaMessage: String?
    @Published private(set) var sessionDownload: UInt64 = 0
    @Published private(set) var sessionUpload: UInt64 = 0

    private let store = UsageStore.shared
    private let settings = SettingsStore.shared

    private var timer: DispatchSourceTimer?
    private var activityToken: NSObjectProtocol?
    private var lastRaw: RawCounters?
    private var lastSampleAt: Date?
    private var wakeObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var didStart = false
    private var skipNextDelta = false

    private init() {
        quota = store.quota
        snapshot = store.snapshot()
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        isRunning = true

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }

        settings.$sampleInterval
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.restartTimer()
                }
            }
            .store(in: &cancellables)

        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .automaticTerminationDisabled],
                reason: "持续采样网络流量"
            )
        }

        sample(initial: true)
        restartTimer()
    }

    func persistNow() {
        store.save(force: true)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
        store.save(force: true)
    }

    // MARK: - Menu bar label

    var menuBarText: String {
        var parts: [String] = []
        for item in MenuBarItem.allCases where settings.enabledMenuItems.contains(item) {
            switch item {
            case .downloadSpeed:
                parts.append("↓" + ByteFormat.compactSpeed(downloadSpeed))
            case .uploadSpeed:
                parts.append("↑" + ByteFormat.compactSpeed(uploadSpeed))
            case .today:
                parts.append("今" + ByteFormat.compactBytes(snapshot.today.total))
            case .week:
                parts.append("周" + ByteFormat.compactBytes(snapshot.week.total))
            case .month:
                parts.append("月" + ByteFormat.compactBytes(snapshot.month.total))
            case .quotaRemaining:
                if let quota {
                    parts.append(quota.isExhausted ? "已用完" : "剩" + ByteFormat.compactBytes(quota.remaining))
                }
            }
        }
        return parts.joined(separator: "  ")
    }

    var recentAverageSpeed: Double {
        let recent = history.suffix(30)
        guard !recent.isEmpty else { return 0 }
        let sum = recent.reduce(0.0) { $0 + $1.download + $1.upload }
        return sum / Double(recent.count)
    }

    // MARK: - Sampling

    private func restartTimer() {
        timer?.cancel()
        let interval = max(1, settings.sampleInterval)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(150)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.sample()
            }
        }
        source.resume()
        timer = source
    }

    private func handleWake() {
        skipNextDelta = true
        restartTimer()
    }

    private func sample(initial: Bool = false) {
        let now = Date()
        let raw = NetworkCounters.read()

        guard let previous = lastRaw, let previousDate = lastSampleAt else {
            lastRaw = raw
            lastSampleAt = now
            downloadSpeed = 0
            uploadSpeed = 0
            snapshot = store.snapshot(now: now)
            return
        }

        let elapsed = now.timeIntervalSince(previousDate)
        defer {
            lastRaw = raw
            lastSampleAt = now
        }

        guard !initial else {
            downloadSpeed = 0
            uploadSpeed = 0
            return
        }

        let delta = raw.delta(from: previous)
        let downDelta = delta.rx
        let upDelta = delta.tx

        // 休眠唤醒、计时器被系统挂起后，累计字节仍然要计入账本和倒计时，
        // 只是不能把整段时间的累计流量当作瞬时速度。
        let hasValidInterval = elapsed >= 0.2 && elapsed <= 30 && !skipNextDelta
        skipNextDelta = false

        if hasValidInterval {
            downloadSpeed = Double(downDelta) / elapsed
            uploadSpeed = Double(upDelta) / elapsed
            history.append(
                SpeedSample(date: now, download: downloadSpeed, upload: uploadSpeed)
            )
            if history.count > 90 {
                history.removeFirst(history.count - 90)
            }
        } else {
            downloadSpeed = 0
            uploadSpeed = 0
        }

        if downDelta > 0 || upDelta > 0 {
            sessionDownload &+= downDelta
            sessionUpload &+= upDelta
            store.addTraffic(down: downDelta, up: upDelta, at: now)
            updateQuota(down: downDelta, up: upDelta)
        }

        snapshot = store.snapshot(now: now)
        store.save()
    }

    // MARK: - Quota

    func startQuota(limitBytes: UInt64) {
        guard limitBytes > 0 else { return }

        QuotaAlertWindowController.shared.close()

        // 先把当前计数作为基线，确保倒计时只统计「点击开始」之后的流量。
        sample(initial: true)

        let record = QuotaRecord(
            limitBytes: limitBytes,
            consumedBytes: 0,
            startedAt: Date(),
            isExhausted: false
        )
        store.quota = record
        store.save(force: true)
        quota = record
        lastQuotaMessage = nil

        if settings.notificationsEnabled {
            NotificationService.shared.requestAuthorization()
        }
    }

    func cancelQuota() {
        QuotaAlertWindowController.shared.close()
        store.quota = nil
        store.save(force: true)
        quota = nil
        lastQuotaMessage = nil
    }

    func refreshSnapshot() {
        snapshot = store.snapshot()
        quota = store.quota
        store.save(force: true)
    }

    func restartQuota() {
        guard let quota else { return }
        startQuota(limitBytes: quota.limitBytes)
    }

    func turnOffWiFi() async throws {
        try await WiFiController.turnOffWiFi()
        lastQuotaMessage = "Wi-Fi 已关闭，流量统计仍在继续。"
    }

    private func updateQuota(down: UInt64, up: UInt64) {
        guard var current = store.quota, current.isExhausted == false else { return }

        current.consumedBytes &+= down &+ up

        if current.consumedBytes >= current.limitBytes {
            current.isExhausted = true
            store.quota = current
            quota = current
            store.save(force: true)
            lastQuotaMessage = nil
            notifyQuotaExhausted(current)
        } else {
            store.quota = current
            quota = current
        }
    }

    private func notifyQuotaExhausted(_ record: QuotaRecord) {
        if settings.playSound {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        if settings.notificationsEnabled {
            NotificationService.shared.postQuotaExhausted(limitBytes: record.limitBytes)
        }
        QuotaAlertWindowController.shared.show(quota: record) { [weak self] in
            self?.lastQuotaMessage = "Wi-Fi 已关闭，流量统计仍在继续。"
        }
    }

    func showQuotaAlertForTesting() {
        let sample = QuotaRecord(
            limitBytes: 2_000_000_000,
            consumedBytes: 2_000_000_000,
            startedAt: Date().addingTimeInterval(-7_800),
            isExhausted: true
        )
        QuotaAlertWindowController.shared.show(quota: sample, isTest: true)
    }
}
