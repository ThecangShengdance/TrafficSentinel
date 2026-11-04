import AppKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var selection: Int

    init(initialTab: Int = 0) {
        _selection = State(initialValue: min(max(initialTab, 0), 2))
    }

    var body: some View {
        TabView(selection: $selection) {
            MenuBarSettingsTab()
                .tabItem { Label("菜单栏", systemImage: "menubar.rectangle") }
                .tag(0)
            GeneralSettingsTab()
                .tabItem { Label("统计与提醒", systemImage: "bell.badge") }
                .tag(1)
            DataSettingsTab()
                .tabItem { Label("数据", systemImage: "internaldrive") }
                .tag(2)
        }
        .frame(width: 520, height: 470)
    }
}

// MARK: - Menu bar

private struct MenuBarSettingsTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection("菜单栏显示内容", subtitle: "可同时显示多项，用两个空格分隔。") {
                VStack(spacing: 0) {
                    ForEach(MenuBarItem.allCases) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.blue)
                                .frame(width: 16)
                            Text(item.title)
                                .font(.system(size: 12))
                            Spacer()
                            Toggle("", isOn: binding(for: item))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                        .padding(.vertical, 5)

                        if item != MenuBarItem.allCases.last {
                            Divider()
                                .padding(.leading, 25)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Text("预览")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(model.menuBarText.isEmpty ? "（空）" : model.menuBarText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    }
                Spacer()
            }

            SettingsSection("外观") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("在文字前显示图标", isOn: $settings.showMenuBarIcon)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    HStack {
                        Text("刷新频率")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $settings.sampleInterval) {
                            Text("1 秒").tag(1.0)
                            Text("2 秒").tag(2.0)
                            Text("5 秒").tag(5.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                }
            }

            if settings.enabledMenuItems.isEmpty && settings.showMenuBarIcon == false {
                Label("当前菜单栏不会显示任何内容，建议至少保留一项或开启图标。", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for item: MenuBarItem) -> Binding<Bool> {
        Binding(
            get: { settings.enabledMenuItems.contains(item) },
            set: { settings.setEnabled($0, for: item) }
        )
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var notifications = NotificationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection("统计") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("流量数字单位")
                                .font(.system(size: 12))
                            Text("日 / 周 / 月卡片的显示方式")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.totalUnit) {
                            ForEach(TotalUnitStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }
            }

            SettingsSection("提醒") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("额度用完时发送系统通知", isOn: $settings.notificationsEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Toggle("额度用完时播放提示音", isOn: $settings.playSound)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    HStack(spacing: 8) {
                        Text("通知权限：\(notificationStatusText)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if notifications.authorizationStatus == .denied {
                            Button("打开系统设置") {
                                openNotificationSettings()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 10))
                        }
                        Button("请求权限") {
                            NotificationService.shared.requestAuthorization(force: true)
                        }
                        .controlSize(.small)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("预览额度提醒")
                                .font(.system(size: 12))
                            Text("查看提醒弹窗的样子，不会关闭 Wi-Fi")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("显示预览") {
                            AppModel.shared.showQuotaAlertForTesting()
                        }
                        .controlSize(.small)
                    }
                }
            }

            SettingsSection("启动") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Text("登录项需要在「系统设置 › 通用 › 登录项」中允许后才会生效。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let error = settings.loginItemError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            NotificationService.shared.refreshStatus()
        }
    }

    private var notificationStatusText: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "未请求"
        @unknown default:
            return "未知"
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Data

private struct DataSettingsTab: View {
    @ObservedObject private var model = AppModel.shared
    @State private var pendingReset: UsageStore.ResetScope?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection("本机流量账本", subtitle: "按天累计，保留最近 400 天。") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("数据文件")
                                .font(.system(size: 11, weight: .medium))
                            Text(UsageStore.shared.storageURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("在 Finder 中显示") {
                            revealStorage()
                        }
                        .controlSize(.small)
                    }

                    Divider()

                    HStack(spacing: 14) {
                        summary("今天", model.snapshot.today.total)
                        summary("本周", model.snapshot.week.total)
                        summary("本月", model.snapshot.month.total)
                    }
                }
            }

            SettingsSection("重置统计", subtitle: "重置流量账本不会影响正在进行中的倒计时。") {
                HStack(spacing: 7) {
                    ForEach([UsageStore.ResetScope.today, .week, .month, .all]) { scope in
                        Button("重置\(scope.title)") {
                            pendingReset = scope
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("流量按 1000 进制统计，与运营商口径一致。", systemImage: "info.circle")
                Label("统计所有 en* 接口：Wi-Fi、有线网络、iPhone USB 共享。", systemImage: "info.circle")
                Label("App 未运行期间产生的流量无法被记录。", systemImage: "info.circle")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "重置\(pendingReset?.title ?? "")流量数据？",
            isPresented: resetBinding,
            titleVisibility: .visible
        ) {
            Button("重置", role: .destructive) {
                if let scope = pendingReset {
                    UsageStore.shared.reset(scope)
                    AppModel.shared.refreshSnapshot()
                }
                pendingReset = nil
            }
            Button("取消", role: .cancel) {
                pendingReset = nil
            }
        } message: {
            Text("此操作不可撤销。")
        }
    }

    private var resetBinding: Binding<Bool> {
        Binding(
            get: { pendingReset != nil },
            set: { newValue in
                if newValue == false {
                    pendingReset = nil
                }
            }
        )
    }

    private func summary(_ title: String, _ bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(ByteFormat.bytes(bytes))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealStorage() {
        let url = UsageStore.shared.storageURL
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? manager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

// MARK: - Shared

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
    }
}
