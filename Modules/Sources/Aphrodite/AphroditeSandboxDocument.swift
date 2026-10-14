import Foundation

public enum AphroditeSandboxDocument {
    public static func make(from generatedHTML: String) -> String {
        let escaped = generatedHTML
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; connect-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'none'; base-uri 'none'; object-src 'none'">
        <style>html,body,iframe{width:100%;height:100%;margin:0;border:0;background:transparent}</style></head>
        <body><iframe sandbox="allow-scripts" srcdoc="\(escaped)"></iframe></body></html>
        """
    }
}
