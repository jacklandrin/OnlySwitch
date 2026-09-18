//
//  PrivilegedAccessView.swift
//  OnlySwitch
//

import SwiftUI

struct PrivilegedAccessView: View {
    @StateObject private var viewModel: PrivilegedAccessViewModel
    @State private var isShowingRemovalConfirmation = false

    init(viewModel: PrivilegedAccessViewModel = .init()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Privileged Switch Access".localized()) {
                LabeledContent("Status".localized(), value: viewModel.presentation.titleKey.localized())
                Text(viewModel.presentation.detailKey.localized())
                    .foregroundStyle(.secondary)

                if let action = viewModel.presentation.primaryAction {
                    primaryActionButton(action)
                }

                if viewModel.status == .enabled || viewModel.status == .disabled {
                    Button("Repair Privileged Access".localized(), action: repair)
                        .disabled(viewModel.isWorking)
                        .accessibilityLabel(Text("Repair privileged switch access".localized()))
                }

                if viewModel.status != .enabled {
                    Button("Open System Settings".localized(), action: openSystemSettings)
                        .disabled(viewModel.isWorking)
                        .accessibilityLabel(Text("Open System Settings to manage privileged access".localized()))
                }

                if viewModel.status != .notInstalled {
                    Button("Remove Privileged Access".localized(), role: .destructive) {
                        isShowingRemovalConfirmation = true
                    }
                    .disabled(viewModel.isWorking)
                    .accessibilityLabel(Text("Remove privileged switch access".localized()))
                }

                if viewModel.isWorking {
                    ProgressView()
                        .accessibilityLabel(Text("Updating privileged switch access".localized()))
                }

                if let messageKey = viewModel.messageKey {
                    Text(messageKey.localized())
                        .foregroundStyle(.secondary)
                        .accessibilityLiveRegion(.assertive)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
        .task { await viewModel.refresh() }
        .confirmationDialog(
            "Remove privileged access?".localized(),
            isPresented: $isShowingRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Privileged Access".localized(), role: .destructive, action: remove)
            Button("Cancel".localized(), role: .cancel) {}
        } message: {
            Text("Supported switches will ask for authorization again if you set them after removal.".localized())
        }
    }

    @ViewBuilder
    private func primaryActionButton(_ action: PrivilegedAccessAction) -> some View {
        switch action {
        case .install:
            Button("Install & Authorize".localized(), action: install)
                .disabled(viewModel.isWorking)
                .accessibilityLabel(Text("Install and authorize privileged switch access".localized()))
        case .repair:
            Button("Repair Privileged Access".localized(), action: repair)
                .disabled(viewModel.isWorking)
                .accessibilityLabel(Text("Repair privileged switch access".localized()))
        case .openSystemSettings:
            Button("Open System Settings".localized(), action: openSystemSettings)
                .disabled(viewModel.isWorking)
                .accessibilityLabel(Text("Open System Settings to approve privileged access".localized()))
        }
    }

    private func install() {
        Task { await viewModel.installOrRepair() }
    }

    private func repair() {
        Task { await viewModel.installOrRepair() }
    }

    private func remove() {
        Task { await viewModel.remove() }
    }

    private func openSystemSettings() {
        Task { await viewModel.openSystemSettings() }
    }
}
