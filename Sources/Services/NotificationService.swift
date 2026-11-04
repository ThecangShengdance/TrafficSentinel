import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    private var hasRequested = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func requestAuthorization(force: Bool = false) {
        guard force || !hasRequested else { return }
        hasRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("[TrafficSentinel] 通知授权失败：\(error.localizedDescription)")
            }
            Task { @MainActor in
                self.refreshStatus()
            }
        }
    }

    func postQuotaExhausted(limitBytes: UInt64) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "流量倒计时已用完"
        content.body = "本次设定的 \(ByteFormat.bytes(limitBytes)) 额度已用完，请检查网络连接。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quota-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[TrafficSentinel] 发送通知失败：\(error.localizedDescription)")
            }
        }
    }
}
