import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 4) {
            if settings.showMenuBarIcon || model.menuBarText.isEmpty {
                Image(systemName: "network")
                    .font(.system(size: 12, weight: .semibold))
            }
            if model.menuBarText.isEmpty == false {
                Text(model.menuBarText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}
