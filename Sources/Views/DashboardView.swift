import AppKit
import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.openSettings) private var openSettings

    private var historySlice: [SpeedSample] {
        Array(model.history.suffix(90))
    }

    private var peakSpeed: Double {
        let down = historySlice.map(\.download).max() ?? 0
        let up = historySlice.map(\.upload).max() ?? 0
        return max(down, up)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            speedRow
            QuotaCard()
            chartCard
            totalsRow
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accentGradient)
                    .frame(width: 34, height: 34)
                Image(systemName: "network")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.blue.opacity(0.35), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("流量哨兵")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    private var statusText: String {
        if let quota = model.quota, quota.isExhausted {
            return "额度已用完"
        }
        if model.quota != nil {
            return "倒计时进行中"
        }
        return "实时监控中"
    }

    private var statusColor: Color {
        if let quota = model.quota, quota.isExhausted {
            return Theme.red
        }
        if model.quota != nil {
            return Theme.amber
        }
        return Theme.green
    }

    // MARK: - Speeds

    private var speedRow: some View {
        HStack(spacing: 10) {
            SpeedCard(
                title: "下载",
                icon: "arrow.down",
                value: model.downloadSpeed,
                tint: Theme.blue,
                history: model.history.suffix(40).map(\.download)
            )
            SpeedCard(
                title: "上传",
                icon: "arrow.up",
                value: model.uploadSpeed,
                tint: Theme.purple,
                history: model.history.suffix(40).map(\.upload)
            )
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("实时速率")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("最近 90 个采样")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                LegendDot(color: Theme.blue, title: "下载")
                LegendDot(color: Theme.purple, title: "上传")
            }

            if historySlice.count >= 2 {
                Chart {
                    ForEach(historySlice) { sample in
                        AreaMark(
                            x: .value("时间", sample.date),
                            y: .value("下载", sample.download)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.blue.opacity(0.30), Theme.blue.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("时间", sample.date),
                            y: .value("下载", sample.download)
                        )
                        .foregroundStyle(Theme.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("时间", sample.date),
                            y: .value("上传", sample.upload)
                        )
                        .foregroundStyle(Theme.purple)
                        .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: [3, 3]))
                        .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: 0...max(peakSpeed * 1.15, 1024))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 84)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .frame(height: 84)
                    .overlay {
                        Text("正在采集速率…")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
            }

            HStack(spacing: 4) {
                Text("本次运行")
                    .foregroundStyle(.tertiary)
                Text("↓\(ByteFormat.compactBytes(model.sessionDownload))")
                    .foregroundStyle(Theme.blue)
                Text("↑\(ByteFormat.compactBytes(model.sessionUpload))")
                    .foregroundStyle(Theme.purple)
                Spacer()
                Text("含 Wi-Fi / 蜂窝")
                    .foregroundStyle(.quaternary)
            }
            .font(.system(size: 9.5, weight: .medium))
            .monospacedDigit()
        }
        .card(padding: 12)
    }

    // MARK: - Totals

    private var totalsRow: some View {
        HStack(spacing: 8) {
            TotalTile(title: "今天", bucket: model.snapshot.today, tint: Theme.blue)
            TotalTile(title: "本周", bucket: model.snapshot.week, tint: Theme.cyan)
            TotalTile(title: "本月", bucket: model.snapshot.month, tint: Theme.purple)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.green)
                .frame(width: 5, height: 5)
            Text("统计中")
                .foregroundStyle(.secondary)
            Text("· 数据仅保存在本机")
                .foregroundStyle(.tertiary)
            Spacer()
            Text("每 \(settings.sampleIntervalText)采样")
                .foregroundStyle(.quaternary)
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }
        .font(.system(size: 9.5))
    }
}

// MARK: - Pieces

private struct SpeedCard: View {
    let title: String
    let icon: String
    let value: Double
    let tint: Color
    let history: [Double]

    private var parts: (value: String, unit: String) {
        ByteFormat.speedParts(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.value)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(parts.unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Sparkline(values: history, color: tint)
                .frame(height: 12)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 11, tint: tint)
    }
}

private struct TotalTile: View {
    let title: String
    let bucket: UsageBucket
    let tint: Color

    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ByteFormat.bytes(bucket.total, style: settings.totalUnit))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("↓\(ByteFormat.compactBytes(bucket.down)) ↑\(ByteFormat.compactBytes(bucket.up))")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10, tint: tint)
    }
}

private struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
