import Foundation
import Extensions
import OSLog

/// A local, isolated page-style adapter. No page code receives a native message handler.
enum BrowserAppearanceScript {
    static let source: String = {
        do {
            let names = ["DarkReader", "BrowserAppearanceController"]
            return try names.map { name in
                guard let url = Bundle.module.url(forResource: name, withExtension: "js") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try String(contentsOf: url, encoding: .utf8)
            }.joined(separator: "\n;\n")
        } catch {
            Logger.browser.error("Loading bundled browser appearance resources failed: \(error.localizedDescription)")
            return ""
        }
    }()
}
