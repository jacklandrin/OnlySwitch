//
//  AgentEvolutionClient+App.swift
//  OnlySwitch
//

import Defines
import Extensions
import Foundation
import OnlyAgent
import OnlySwitchPersistence

extension AgentEvolutionClient {
    /// An Only Agent plan becomes a user-authored AppleScript button. It never
    /// carries a privileged operation; `addItem` re-derives that from the
    /// compiled allowlist, which excludes user-authored Evolutions.
    static func makeEvolutionItem(_ draft: AgentEvolutionDraft, id: UUID) -> EvolutionItem {
        EvolutionItem(
            id: id,
            name: draft.name,
            active: true,
            iconName: "sparkles",
            controlType: .Button,
            singleCommand: EvolutionCommand(
                executeType: .applescript,
                commandType: .single,
                commandString: draft.command,
                debugStatus: .success
            )
        )
    }

    /// Shows a native password dialog for `sudo -A` when a saved button runs.
    static let askpassScript = """
    #!/bin/sh
    exec /usr/bin/osascript - "${1:-Password:}" <<'APPLESCRIPT'
    on run argv
        set answer to display dialog (item 1 of argv) default answer "" with hidden answer with title "OnlySwitch" with icon caution buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel"
        return text returned of answer
    end run
    APPLESCRIPT

    """

    static func installAskpass(in directory: URL) throws -> String {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appending(path: "askpass")
        try Data(askpassScript.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    static let app = Self(saveButton: { draft in
        try await MainActor.run {
            let item = makeEvolutionItem(draft, id: UUID())
            try EvolutionCommandEntity.addItem(item: item)
            var ids = UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String] ?? []
            if !ids.contains(item.id.uuidString) {
                ids.append(item.id.uuidString)
            }
            UserDefaults.standard.set(ids, forKey: UserDefaults.Key.evolutionIDs)
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    }, installAskpass: {
        let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "OnlySwitch"
        return try installAskpass(
            in: URL.applicationSupportDirectory.appending(path: "\(bundleName)/OnlyAgent", directoryHint: .isDirectory)
        )
    })
}
