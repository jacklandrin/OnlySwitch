//
//  CodexSettingView.swift
//  Modules
//
//  Created by Codex on 28.03.26.
//

import ComposableArchitecture
import Design
import SwiftUI

@available(macOS 26.0, *)
public struct CodexSettingView: View {
    @SwiftUI.Bindable var store: StoreOf<CodexSettingReducer>

    public init(store: StoreOf<CodexSettingReducer>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Authorization:".localized())
                        Spacer()
                    }

                    HStack {
                        if store.isAuthorizing || store.isSigningOut {
                            AppKitProgressView()
                                .scaleEffect(0.6)
                        }

                        Button {
                            store.send(.signIn)
                        } label: {
                            Text((store.isSignedIn ? "Re-authorize with ChatGPT" : "Sign In With ChatGPT").localized())
                        }
                        .disabled(store.isAuthorizing || store.isSigningOut)

                        if store.isSignedIn {
                            Button {
                                store.send(.signOut)
                            } label: {
                                Text("Sign Out".localized())
                            }
                            .disabled(store.isAuthorizing || store.isSigningOut)
                        }
                    }
                    if let email = store.accountEmail {
                        HStack {
                            Text("Signed in as %@".localizeWithFormat(arguments: email))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        if let plan = store.plan {
                            HStack {
                                Text("Plan: %@".localizeWithFormat(arguments: plan))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }

                    HStack {
                        Text("Models:".localized())
                        Spacer()
                    }
                    ForEach(store.models, id: \.self) { model in
                        VStack {
                            HStack {
                                Text(model)
                                Spacer()
                            }
                            .frame(height: 26)
                            Divider()
                        }
                    }

                    if let authError = store.authError {
                        HStack {
                            Text("❌ \(authError)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .onAppear {
                store.send(.appear)
            }
        }
    }
}

#Preview {
    if #available(macOS 26.0, *) {
        CodexSettingView(store: .init(initialState: .init(), reducer: CodexSettingReducer.init))
    }
}
