//
//  AuthenticatorImportSheet.swift
//  OnlySwitch
//

import SwiftUI
import Extensions

struct AuthenticatorImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AuthenticatorStore.shared

    @State private var input: String = ""
    @State private var errorMessage: String?
    @State private var importedCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Authenticator QR Result".localized())
                .font(.headline)

            Text("Paste the QR scan result (supports `otpauth://...` and Google Authenticator `otpauth-migration://...`).".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.gray.opacity(0.35), lineWidth: 1)
                )

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            } else if let importedCount {
                Text(String(format: "Imported %lld account(s).".localized(), Int64(importedCount)))
                    .foregroundColor(.green)
                    .font(.footnote)
            }

            HStack {
                Spacer()
                Button("Cancel".localized()) { dismiss() }
                Button("Import".localized()) {
                    do {
                        let count = try store.importFromScanResult(input)
                        importedCount = count
                        errorMessage = nil
                        if count > 0 {
                            store.enabled = true
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        importedCount = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}

