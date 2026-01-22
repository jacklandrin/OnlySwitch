//
//  AuthenticatorPanelView.swift
//  OnlySwitch
//

import SwiftUI
import AppKit
import Defines
import Extensions

struct AuthenticatorPanelView: View {
    @ObservedObject private var store = AuthenticatorStore.shared
    @State private var showImport = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
                .opacity(0.25)
                .frame(height: 1)

            if store.enabled && isExpanded {
                if store.accounts.isEmpty {
                    emptyRow
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 0) {
                            ForEach(store.accounts) { account in
                                AuthenticatorCodeRow(account: account, now: context.date) {
                                    withAnimation(.spring()) {
                                        isExpanded = false
                                    }
                                }
                                Divider()
                                    .opacity(0.25)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            AuthenticatorImportSheet()
        }
    }

    private var headerRow: some View {
        HStack {
            Image(systemName: "key.fill")
                .font(.system(size: 18))
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .foregroundColor(.accentColor)
                .padding(.trailing, 8)

            Button {
                withAnimation(.spring()) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Authenticator".localized())
                        .font(.system(size: 14))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Text(accountSummary)
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring()) { isExpanded.toggle() }
        }
    }

    private var emptyRow: some View {
        HStack {
            Spacer()
                .frame(width: Layout.iconSize)
                .padding(.trailing, 8)
            Text("No accounts. Import in Settings > Authenticator.".localized())
                .foregroundColor(.gray)
                .font(.system(size: 14))
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }

    private var accountSummary: String {
        let count = store.accounts.count
        if count == 0 { return "" }
        if count == 1 { return "1 account".localized() }
        return "\(count) accounts".localized()
    }
}

private struct AuthenticatorCodeRow: View {
    let account: AuthenticatorAccount
    let now: Date
    let onCopied: () -> Void
    @ObservedObject private var store = AuthenticatorStore.shared

    var body: some View {
        let secret = store.secret(for: account)
        let totp = secret.flatMap { TOTP.code(secret: $0, digits: account.digits, period: account.period, algorithm: account.algorithm, date: now) }
        let code = totp?.code ?? "------"
        let remaining = totp?.remaining ?? account.period

        HStack(spacing: 10) {
            Spacer()
                .frame(width: Layout.iconSize)
                .padding(.trailing, 8)

            Text(account.displayName)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer()

            Text(code)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)

            Text("\(remaining)s")
                .foregroundColor(.gray)
                .font(.system(size: 13))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                onCopied()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(Text("Copy"))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }
}
