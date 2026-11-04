import AppKit
import SwiftUI

@MainActor
final class QuotaAlertWindowController {
    static let shared = QuotaAlertWindowController()

    private var panel: NSPanel?
    private var onWiFiOff: (() -> Void)?

    private init() {}

    func show(quota: QuotaRecord, isTest: Bool = false, onWiFiOff: (() -> Void)? = nil) {
        close()
        self.onWiFiOff = onWiFiOff

        let view = QuotaAlertView(
            quota: quota,
            isTest: isTest,
            onClose: { [weak self] in self?.close() },
            onWiFiOff: { [weak self] in self?.onWiFiOff?() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 380, height: 360)
        host.layoutSubtreeIfNeeded()

        let fitting = host.fittingSize
        let size = NSSize(width: 380, height: fitting.height > 100 ? fitting.height : 360)

        let panel = AlertPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.setContentSize(size)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + 30
            )
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        onWiFiOff = nil
    }
}

private final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct QuotaAlertView: View {
    let quota: QuotaRecord
    let isTest: Bool
    let onClose: () -> Void
    let onWiFiOff: () -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            message
            stats
            actionArea
            footer
        }
        .padding(20)
        .frame(width: 380)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                }
        }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.red.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.red)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isTest ? "提醒预览" : "流量额度已用完")
                    .font(.system(size: 17, weight: .bold))
                Text(isTest ? "这是测试弹窗，不会真的关闭 Wi-Fi。" : "设定的流量倒计时已经归零。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
    }

    private var message: some View {
        Text("从 \(DateText.start(quota.startedAt)) 开始统计，下载 + 上传合计已达到 \(ByteFormat.bytes(quota.limitBytes))。")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stats: some View {
        HStack(spacing: 8) {
            AlertStat(title: "已用流量", value: ByteFormat.bytes(quota.consumedBytes), tint: Theme.red)
            AlertStat(title: "已运行", value: DurationText.short(Date().timeIntervalSince(quota.startedAt)), tint: .primary)
            AlertStat(title: "设定额度", value: ByteFormat.bytes(quota.limitBytes), tint: Theme.blue)
        }
    }

    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 9) {
            if isTest == false {
                Text("是否立即关闭 Wi-Fi，避免流量继续超出？")
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isTest {
                Button("知道了", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    Button {
                        turnOffWiFi()
                    } label: {
                        HStack(spacing: 5) {
                            if isWorking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "wifi.slash")
                            }
                            Text("关闭 Wi-Fi")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.red)
                    .disabled(isWorking)

                    Button("保持连接", action: onClose)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
            Text("关闭 Wi-Fi 后，仍会继续统计其它网络接口的流量。")
            Spacer()
            if isTest {
                Text("预览模式")
                    .foregroundStyle(Theme.amber)
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.tertiary)
    }

    private func turnOffWiFi() {
        guard isTest == false else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await AppModel.shared.turnOffWiFi()
                onWiFiOff()
                onClose()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

private struct AlertStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }
}
