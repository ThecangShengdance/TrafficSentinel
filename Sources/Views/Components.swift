import SwiftUI

struct SpeedSample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let download: Double
    let upload: Double
}

enum Theme {
    static let blue = Color(red: 0.24, green: 0.52, blue: 0.98)
    static let cyan = Color(red: 0.13, green: 0.72, blue: 0.90)
    static let purple = Color(red: 0.60, green: 0.40, blue: 0.98)
    static let green = Color(red: 0.18, green: 0.75, blue: 0.45)
    static let amber = Color(red: 0.98, green: 0.65, blue: 0.12)
    static let red = Color(red: 0.95, green: 0.30, blue: 0.28)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [blue, cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func card(padding: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(CardStyle(padding: padding, tint: tint))
    }
}

private struct CardStyle: ViewModifier {
    let padding: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint?.opacity(0.09) ?? Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(tint?.opacity(0.16) ?? Color.primary.opacity(0.06), lineWidth: 0.8)
            }
    }
}

enum DateText {
    private static let startFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static func start(_ date: Date) -> String {
        startFormatter.string(from: date)
    }
}

enum DurationText {
    static func short(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes > 0 ? "\(hours) 小时 \(remainingMinutes) 分" : "\(hours) 小时"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours > 0 ? "\(days) 天 \(remainingHours) 小时" : "\(days) 天"
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(values.max() ?? 1, 1)
            Path { path in
                guard values.count > 1 else { return }
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = geometry.size.height * (1 - CGFloat(min(max(value, 0), maximum) / maximum))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

