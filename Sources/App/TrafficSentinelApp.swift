import AppKit
import SwiftUI

@main
struct TrafficSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .onAppear {
                    AppModel.shared.start()
                }
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var debugWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()

        #if DEBUG
        handleDebugArguments()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
        QuotaAlertWindowController.shared.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    #if DEBUG
    private func handleDebugArguments() {
        let arguments = CommandLine.arguments

        if arguments.contains("--show-test-alert") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                AppModel.shared.showQuotaAlertForTesting()
            }
        }

        if arguments.contains("--test-alert-live") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                let sample = QuotaRecord(
                    limitBytes: 2_000_000_000,
                    consumedBytes: 2_000_000_000,
                    startedAt: Date().addingTimeInterval(-7_800),
                    isExhausted: true
                )
                QuotaAlertWindowController.shared.show(quota: sample) {}
            }
        }

        if arguments.contains("--open-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showDashboardWindow()
            }
        }

        if arguments.contains("--open-settings") {
            let tab = value(after: "--settings-tab").flatMap { Int($0) } ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.showSettingsWindow(tab: tab)
            }
        }

        if let raw = value(after: "--quota-test"), let megabytes = Double(raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                AppModel.shared.cancelQuota()
                AppModel.shared.startQuota(limitBytes: UInt64(megabytes * 1_000_000))
            }
        }

        if arguments.contains("--reset-usage") {
            UsageStore.shared.reset(.all)
            UsageStore.shared.quota = nil
            UsageStore.shared.save(force: true)
            AppModel.shared.refreshSnapshot()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.terminate(nil)
            }
        }
    }

    private func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        return arguments[next]
    }

    private func showSettingsWindow(tab: Int) {
        let host = NSHostingView(rootView: SettingsView(initialTab: tab))
        let size = NSSize(width: 520, height: 470)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "流量哨兵设置"
        window.contentView = host
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow = window
    }

    private func showDashboardWindow() {
        let host = NSHostingView(rootView: DashboardView())
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "流量哨兵"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow = window
    }
    #endif
}
