import SwiftUI

struct QuotaCard: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var settings = SettingsStore.shared

    @State private var amountText = ""
    @State private var unit: QuotaUnit = .gb
    @State private var confirmWiFiOff = false
    @State private var isTurningOffWiFi = false
    @State private var actionError: String?

    private struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let amount: String
        let unit: QuotaUnit
    }

    private let presets: [Preset] = [
        Preset(label: "500M", amount: "500", unit: .mb),
        Preset(label: "1G", amount: "1", unit: .gb),
        Preset(label: "2G", amount: "2", unit: .gb),
        Preset(label: "5G", amount: "5", unit: .gb)
    ]

    private var quota: QuotaRecord? { model.quota }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let quota {
                activeContent(quota)
            } else {
                setupContent
            }

            if let actionError {
                Text(actionError)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.lastQuotaMessage {
                Label(message, systemImage: "wifi.slash")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .card(padding: 12, tint: quota?.isExhausted == true ? Theme.red : nil)
        .onAppear(perform: prepareInput)
        .confirmationDialog(
            "关闭 Wi-Fi？",
            isPresented: $confirmWiFiOff,
            titleVisibility: .visible
        ) {
            Button("关闭 Wi-Fi", role: .destructive) {
                turnOffWiFi()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("关闭后需要重新打开 Wi-Fi 才能联网（部分机型需要管理员密码）。")
        }
    }

    // MARK: - Empty state

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Text("流量倒计时")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                StatusBadge(text: "未启用", color: .secondary)
            }

            Text("设定剩余额度后，从此刻起统计下载 + 上传，用完立即提醒。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    TextField("2", text: $amountText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(width: 46)
                    Text(unit.title)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                }

                Picker("单位", selection: $unit) {
                    ForEach(QuotaUnit.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 94)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button("开始") {
                    startQuota()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.blue)
                .disabled(enteredBytes == nil)
            }

            HStack(spacing: 5) {
                Text("常用")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach(presets) { preset in
                    Button(preset.label) {
                        amountText = preset.amount
                        unit = preset.unit
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Theme.blue.opacity(0.10)))
                }
            }
        }
    }

    // MARK: - Active state

    @ViewBuilder
    private func activeContent(_ quota: QuotaRecord) -> some View {
        HStack(spacing: 6) {
            Image(systemName: quota.isExhausted ? "exclamationmark.triangle.fill" : "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(quota.isExhausted ? Theme.red : Theme.blue)
            Text("流量倒计时")
                .font(.system(size: 11.5, weight: .semibold))
            Spacer()
            StatusBadge(
                text: quota.isExhausted ? "额度已用完" : "进行中",
                color: quota.isExhausted ? Theme.red : Theme.green
            )
        }

        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(quota.isExhausted ? "0 B" : ByteFormat.bytes(quota.remaining))
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(quota.isExhausted ? Theme.red : .primary)
            Text("剩余")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text("共 \(ByteFormat.bytes(quota.limitBytes))")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }

        QuotaBar(progress: quota.progress, exhausted: quota.isExhausted)

        HStack(spacing: 8) {
            stat("已用", ByteFormat.bytes(quota.consumedBytes))
            stat("已运行", DurationText.short(Date().timeIntervalSince(quota.startedAt)))
            stat("预计可用", estimateText(for: quota))
        }

        HStack(spacing: 8) {
            Button {
                confirmWiFiOff = true
            } label: {
                HStack(spacing: 4) {
                    if isTurningOffWiFi {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "wifi.slash")
                    }
                    Text("关闭 Wi-Fi")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Theme.red)
            .disabled(isTurningOffWiFi)

            if quota.isExhausted {
                Button("重新设定") {
                    model.restartQuota()
                    actionError = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            Button("取消倒计时") {
                model.cancelQuota()
                actionError = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func estimateText(for quota: QuotaRecord) -> String {
        guard quota.isExhausted == false else { return "—" }
        let speed = model.recentAverageSpeed
        guard speed > 1 else { return "无流量活动" }
        let seconds = Double(quota.remaining) / speed
        guard seconds < 60 * 60 * 24 * 60 else { return "60 天以上" }
        return "约 " + DurationText.short(seconds)
    }

    // MARK: - Actions

    private var enteredBytes: UInt64? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value.isFinite else { return nil }
        let bytes = value * Double(unit.bytesPerUnit)
        guard bytes >= 1, bytes <= Double(UInt64.max) else { return nil }
        return UInt64(bytes)
    }

    private func prepareInput() {
        guard amountText.isEmpty else { return }
        amountText = Self.format(settings.defaultQuotaValue)
        unit = settings.defaultQuotaUnit
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func startQuota() {
        guard let bytes = enteredBytes else { return }
        settings.defaultQuotaUnit = unit
        settings.defaultQuotaValue = Double(bytes) / Double(unit.bytesPerUnit)
        actionError = nil
        model.startQuota(limitBytes: bytes)
    }

    private func turnOffWiFi() {
        actionError = nil
        isTurningOffWiFi = true
        Task {
            defer { isTurningOffWiFi = false }
            do {
                try await model.turnOffWiFi()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

private struct QuotaBar: View {
    let progress: Double
    let exhausted: Bool

    private var fill: AnyShapeStyle {
        if exhausted {
            return AnyShapeStyle(Theme.red)
        }
        if progress >= 0.9 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Theme.amber, Theme.red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(Theme.accentGradient)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(fill)
                    .frame(width: barWidth(in: geometry.size.width))
            }
        }
        .frame(height: 7)
        .animation(.easeOut(duration: 0.3), value: progress)
    }

    private func barWidth(in total: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return 0 }
        return max(total * clamped, 6)
    }
}
