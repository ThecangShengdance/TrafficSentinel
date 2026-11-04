import Foundation

/// 字节 / 速率格式化。使用 1000 进制，与运营商流量计费口径一致。
enum ByteFormat {
    private static let step: Double = 1000
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    // MARK: - Speed

    static func speedParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let (value, unit) = scaled(max(0, bytesPerSecond))
        guard unit != "B" else {
            return ("\(Int(value.rounded()))", "B/s")
        }
        let text: String
        if value >= 100 {
            text = String(format: "%.0f", value)
        } else if value >= 10 {
            text = String(format: "%.1f", value)
        } else {
            text = trim(String(format: "%.2f", value))
        }
        return (text, "\(unit)/s")
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        let parts = speedParts(bytesPerSecond)
        return "\(parts.value) \(parts.unit)"
    }

    /// 菜单栏用的紧凑写法，例如 `1.2MB/s`、`0B/s`。
    static func compactSpeed(_ bytesPerSecond: Double) -> String {
        let parts = speedParts(bytesPerSecond)
        return parts.value + parts.unit
    }

    // MARK: - Volume

    static func bytes(_ value: UInt64, style: TotalUnitStyle = .auto) -> String {
        switch style {
        case .auto:
            let (number, unit) = scaled(Double(value))
            return full(number, unit: unit)
        case .gb:
            return String(format: "%.2f GB", Double(value) / 1_000_000_000)
        case .mb:
            return String(format: "%.1f MB", Double(value) / 1_000_000)
        }
    }

    /// 菜单栏用的紧凑写法，例如 `3.4G`、`820M`、`0B`。
    static func compactBytes(_ value: UInt64) -> String {
        let (number, unit) = scaled(Double(value))
        guard unit != "B" else { return "\(Int(number.rounded()))B" }
        if number >= 100 {
            return "\(Int(number.rounded()))\(unit)"
        }
        if number >= 10 {
            return String(format: "%.0f%@", number, unit)
        }
        return trim(String(format: "%.1f", number)) + unit
    }

    // MARK: - Helpers

    private static func scaled(_ value: Double) -> (Double, String) {
        var number = value
        var index = 0
        while number >= step, index < units.count - 1 {
            number /= step
            index += 1
        }
        return (number, units[index])
    }

    private static func full(_ number: Double, unit: String) -> String {
        let text: String
        if number >= 100 {
            text = String(format: "%.0f", number)
        } else if number >= 10 {
            text = String(format: "%.1f", number)
        } else {
            text = trim(String(format: "%.2f", number))
        }
        return "\(text) \(unit)"
    }

    private static func trim(_ string: String) -> String {
        var result = string
        while result.contains("."), result.hasSuffix("0") || result.hasSuffix(".") {
            result.removeLast()
        }
        return result
    }
}
