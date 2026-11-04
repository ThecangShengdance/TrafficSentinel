import Foundation
import ServiceManagement

enum MenuBarItem: String, CaseIterable, Codable, Identifiable {
    case downloadSpeed
    case uploadSpeed
    case today
    case week
    case month
    case quotaRemaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloadSpeed: return "下载速度"
        case .uploadSpeed: return "上传速度"
        case .today: return "今日流量"
        case .week: return "本周流量"
        case .month: return "本月流量"
        case .quotaRemaining: return "倒计时剩余"
        }
    }

    var icon: String {
        switch self {
        case .downloadSpeed: return "arrow.down.circle"
        case .uploadSpeed: return "arrow.up.circle"
        case .today: return "sun.max"
        case .week: return "calendar"
        case .month: return "calendar.circle"
        case .quotaRemaining: return "timer"
        }
    }
}

enum TotalUnitStyle: String, CaseIterable, Codable, Identifiable {
    case auto
    case gb
    case mb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动"
        case .gb: return "固定 GB"
        case .mb: return "固定 MB"
        }
    }
}

enum QuotaUnit: String, CaseIterable, Identifiable {
    case mb
    case gb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mb: return "MB"
        case .gb: return "GB"
        }
    }

    var bytesPerUnit: UInt64 {
        switch self {
        case .mb: return 1_000_000
        case .gb: return 1_000_000_000
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let menuItems = "ts.menuBarItems"
        static let showIcon = "ts.showMenuBarIcon"
        static let sampleInterval = "ts.sampleInterval"
        static let totalUnit = "ts.totalUnit"
        static let notifications = "ts.notificationsEnabled"
        static let playSound = "ts.playSound"
        static let defaultQuotaValue = "ts.defaultQuotaValue"
        static let defaultQuotaUnit = "ts.defaultQuotaUnit"
    }

    private let defaults = UserDefaults.standard
    private var isLoading = true

    @Published var enabledMenuItems: [MenuBarItem] {
        didSet { persist() }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { persist() }
    }
    @Published var sampleInterval: Double {
        didSet { persist() }
    }
    @Published var totalUnit: TotalUnitStyle {
        didSet { persist() }
    }
    @Published var notificationsEnabled: Bool {
        didSet { persist() }
    }
    @Published var playSound: Bool {
        didSet { persist() }
    }
    @Published var defaultQuotaValue: Double {
        didSet { persist() }
    }
    @Published var defaultQuotaUnit: QuotaUnit {
        didSet { persist() }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isLoading, oldValue != launchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }
    @Published private(set) var loginItemError: String?

    private init() {
        let storedItems = defaults.stringArray(forKey: Key.menuItems)
        if let storedItems {
            enabledMenuItems = MenuBarItem.allCases.filter { storedItems.contains($0.rawValue) }
        } else {
            enabledMenuItems = [.downloadSpeed, .uploadSpeed, .today]
        }

        showMenuBarIcon = defaults.bool(forKey: Key.showIcon)

        let interval = defaults.double(forKey: Key.sampleInterval)
        sampleInterval = [1.0, 2.0, 5.0].contains(interval) ? interval : 1.0

        totalUnit = TotalUnitStyle(rawValue: defaults.string(forKey: Key.totalUnit) ?? "") ?? .auto

        if defaults.object(forKey: Key.notifications) == nil {
            notificationsEnabled = true
        } else {
            notificationsEnabled = defaults.bool(forKey: Key.notifications)
        }

        if defaults.object(forKey: Key.playSound) == nil {
            playSound = true
        } else {
            playSound = defaults.bool(forKey: Key.playSound)
        }

        let quotaValue = defaults.double(forKey: Key.defaultQuotaValue)
        defaultQuotaValue = quotaValue > 0 ? quotaValue : 2
        defaultQuotaUnit = QuotaUnit(rawValue: defaults.string(forKey: Key.defaultQuotaUnit) ?? "") ?? .gb

        launchAtLogin = SMAppService.mainApp.status == .enabled
        isLoading = false
    }

    var sampleIntervalText: String {
        switch sampleInterval {
        case 1: return "1 秒"
        case 2: return "2 秒"
        default: return "5 秒"
        }
    }

    func setEnabled(_ enabled: Bool, for item: MenuBarItem) {
        var items = Set(enabledMenuItems)
        if enabled {
            items.insert(item)
        } else {
            items.remove(item)
        }
        enabledMenuItems = MenuBarItem.allCases.filter { items.contains($0) }
    }

    private func persist() {
        guard !isLoading else { return }
        defaults.set(enabledMenuItems.map(\.rawValue), forKey: Key.menuItems)
        defaults.set(showMenuBarIcon, forKey: Key.showIcon)
        defaults.set(sampleInterval, forKey: Key.sampleInterval)
        defaults.set(totalUnit.rawValue, forKey: Key.totalUnit)
        defaults.set(notificationsEnabled, forKey: Key.notifications)
        defaults.set(playSound, forKey: Key.playSound)
        defaults.set(defaultQuotaValue, forKey: Key.defaultQuotaValue)
        defaults.set(defaultQuotaUnit.rawValue, forKey: Key.defaultQuotaUnit)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    loginItemError = "已注册，但需要在「系统设置 › 通用 › 登录项」中允许后才能生效。"
                } else {
                    loginItemError = nil
                }
            } else {
                try SMAppService.mainApp.unregister()
                loginItemError = nil
            }
        } catch {
            loginItemError = error.localizedDescription
            isLoading = true
            launchAtLogin.toggle()
            isLoading = false
        }
    }
}
