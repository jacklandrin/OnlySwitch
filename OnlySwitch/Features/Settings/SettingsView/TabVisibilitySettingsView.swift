//
//  TabVisibilitySettingsView.swift
//  OnlySwitch
//

import SwiftUI
import Utilities

struct TabVisibilitySettingsView: View {
    @StateObject private var viewModel = TabVisibilitySettingsVM()
    @ObservedObject private var langManager = LanguageManager.sharedManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                ForEach(viewModel.sections, id: \.self) { section in
                    Toggle(isOn: binding(for: section)) {
                        Label {
                            Text(section.title)
                        } icon: {
                            SectionBarIcon(section: section, logoSize: 14)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Visible Tabs".localized())
            } footer: {
                Text("Choose which tabs appear in the switch list and Only Control. Controls is always shown.".localized())
            }
        }
        .formStyle(.grouped)
        .tint(colorScheme == .dark ? .mint : .accentColor)
        .id(langManager.currentLang)
    }

    private func binding(for section: SectionBar.Section) -> Binding<Bool> {
        Binding(
            get: { viewModel.isVisible(section) },
            set: { viewModel.setVisible($0, for: section) }
        )
    }
}

#if DEBUG
#Preview {
    TabVisibilitySettingsView()
}
#endif
