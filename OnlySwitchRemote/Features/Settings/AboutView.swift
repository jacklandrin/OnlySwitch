import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: versionDescription)
                LabeledContent("Copyright", value: "© 2021–2026 Jacklandrin")
                Link(destination: URL(string: "https://onlyswitch.click/#/privacy-policy")!) {
                    Text("Privacy Policy")
                }
            }
        }
        .navigationTitle("About")
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let build, build.isEmpty == false else {
            return version
        }
        return "\(version) (\(build))"
    }
}
