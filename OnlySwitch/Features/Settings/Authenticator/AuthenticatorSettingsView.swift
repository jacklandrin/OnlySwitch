//
//  AuthenticatorSettingsView.swift
//  OnlySwitch
//

import SwiftUI
import AppKit
import Extensions

struct AuthenticatorSettingsView: View {
    @ObservedObject private var store = AuthenticatorStore.shared
    @State private var showImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Authenticator".localized())
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Toggle("Enabled".localized(), isOn: $store.enabled)
                    .toggleStyle(.switch)
            }

            HStack {
                Button("Import".localized()) { showImport = true }
                Button("Delete All".localized()) { store.deleteAll() }
                    .disabled(store.accounts.isEmpty)
                Spacer()
            }

            Divider()

            if store.accounts.isEmpty {
                Text("No accounts. Use Import to add one.".localized())
                    .foregroundColor(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    List {
                        ForEach(store.accounts) { account in
                            AuthenticatorSettingsRow(account: account, now: context.date)
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                let account = store.accounts[idx]
                                store.deleteAccount(account)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .sheet(isPresented: $showImport) {
            AuthenticatorImportSheet()
        }
    }
}

private struct AuthenticatorSettingsRow: View {
    let account: AuthenticatorAccount
    let now: Date
    @ObservedObject private var store = AuthenticatorStore.shared

    var body: some View {
        let secret = store.secret(for: account)
        let totp = secret.flatMap { TOTP.code(secret: $0, digits: account.digits, period: account.period, algorithm: account.algorithm, date: now) }
        let code = totp?.code ?? "------"
        let remaining = totp?.remaining ?? account.period

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .lineLimit(1)
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(remaining)s")
                .foregroundColor(.secondary)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
    }
}
