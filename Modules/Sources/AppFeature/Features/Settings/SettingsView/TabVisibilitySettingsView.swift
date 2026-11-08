//
//  TabVisibilitySettingsView.swift
//  OnlySwitch
//

import SwiftUI
import UniformTypeIdentifiers
import Utilities

struct TabVisibilitySettingsView: View {
    @StateObject private var viewModel = TabVisibilitySettingsVM()
    @ObservedObject private var langManager = LanguageManager.sharedManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var draggedSection: SectionBar.Section?

    var body: some View {
        Form {
            Section {
                ForEach(viewModel.sections, id: \.self) { section in
                    row(for: section)
                        .contextMenu {
                            Button("Move Up".localized()) { viewModel.move(section, by: -1) }
                                .disabled(!viewModel.canMove(section, by: -1))
                            Button("Move Down".localized()) { viewModel.move(section, by: 1) }
                                .disabled(!viewModel.canMove(section, by: 1))
                        }
                }
            } header: {
                HStack {
                    Text("Visible Tabs".localized())
                    Spacer()
                    reorderButton
                }
            } footer: {
                Text("Choose which tabs appear in the switch list and Only Control. Click Reorder, then drag tabs to change their order. Controls is always shown first.".localized())
            }
        }
        .formStyle(.grouped)
        .tint(colorScheme == .dark ? .mint : .accentColor)
        .animation(.default, value: viewModel.sections)
        .animation(.default, value: viewModel.isReordering)
    }

    @ViewBuilder
    private func row(for section: SectionBar.Section) -> some View {
        if viewModel.isReordering {
            HStack {
                label(for: section)
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onDrag {
                draggedSection = section
                return NSItemProvider(object: section.rawValue as NSString)
            }
            .onDrop(of: [.plainText], delegate: TabReorderDropDelegate(
                target: section,
                draggedSection: $draggedSection,
                move: { viewModel.move($0, onto: $1) }
            ))
            .accessibilityAction(named: Text("Move Up".localized())) { viewModel.move(section, by: -1) }
            .accessibilityAction(named: Text("Move Down".localized())) { viewModel.move(section, by: 1) }
        } else {
            Toggle(isOn: binding(for: section)) {
                label(for: section)
            }
        }
    }

    private func label(for section: SectionBar.Section) -> some View {
        Label {
            Text(section.title)
        } icon: {
            SectionBarIcon(section: section, logoSize: 14)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var reorderButton: some View {
        let title = viewModel.isReordering ? "Done".localized() : "Reorder".localized()
        let symbol = viewModel.isReordering ? "checkmark" : "arrow.up.arrow.down"
        if #available(macOS 26.0, *) {
            Button { viewModel.toggleReordering() } label: { Label(title, systemImage: symbol) }
                .buttonStyle(.glass)
                .controlSize(.small)
        } else {
            Button { viewModel.toggleReordering() } label: { Label(title, systemImage: symbol) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func binding(for section: SectionBar.Section) -> Binding<Bool> {
        Binding(
            get: { viewModel.isVisible(section) },
            set: { viewModel.setVisible($0, for: section) }
        )
    }
}

/// Moves the dragged tab live as it passes over other rows, like a native reorderable list.
private struct TabReorderDropDelegate: DropDelegate {
    let target: SectionBar.Section
    @Binding var draggedSection: SectionBar.Section?
    let move: (SectionBar.Section, SectionBar.Section) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedSection, draggedSection != target else { return }
        move(draggedSection, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSection = nil
        return true
    }
}

#if DEBUG
#Preview {
    TabVisibilitySettingsView()
}
#endif
