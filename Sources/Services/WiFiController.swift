import CoreWLAN
import Foundation

enum WiFiControlError: LocalizedError {
    case noInterface
    case commandFailed(String)
    case canceled

    var errorDescription: String? {
        switch self {
        case .noInterface:
            return "没有找到 Wi-Fi 网卡。"
        case .canceled:
            return "已取消管理员授权，Wi-Fi 未关闭。"
        case .commandFailed(let message):
            return "关闭 Wi-Fi 失败：\(message)"
        }
    }
}

enum WiFiController {
    static var interfaceName: String {
        CWWiFiClient.shared().interface()?.interfaceName ?? "en0"
    }

    static var isWiFiOn: Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }

    /// 优先调用 CoreWLAN 直接关闭；系统拒绝时回退到需要管理员授权的 networksetup。
    static func turnOffWiFi() async throws {
        guard isWiFiOn else { return }

        if let interface = CWWiFiClient.shared().interface() {
            do {
                try interface.setPower(false)
                if interface.powerOn() == false {
                    return
                }
            } catch {
                // 继续走下方需要授权的路径。
            }
        }

        try await setPowerUsingNetworksetup(interface: interfaceName, on: false)
    }

    static func turnOnWiFi() async throws {
        guard isWiFiOn == false else { return }
        try await setPowerUsingNetworksetup(interface: interfaceName, on: true)
    }

    private static func setPowerUsingNetworksetup(interface: String, on: Bool) async throws {
        let command = "/usr/sbin/networksetup -setairportpower \(interface) \(on ? "on" : "off")"
        let script = "do shell script \"\(command)\" with administrator privileges"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()

            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                    return
                }
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if raw.contains("-128") || raw.localizedCaseInsensitiveContains("canceled") {
                    continuation.resume(throwing: WiFiControlError.canceled)
                } else {
                    continuation.resume(
                        throwing: WiFiControlError.commandFailed(
                            raw.isEmpty ? "退出码 \(finished.terminationStatus)" : raw
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
