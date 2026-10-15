import Foundation

public enum AphroditeSandboxDocument {
    public static let wrapperBaseURL = URL(string: "\(AphroditeAppOrigin.scheme)://wrapper/")!

    public static func make(origin: AphroditeAppOrigin) -> String {
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src \(Self.schemeSource); style-src 'unsafe-inline'; base-uri 'none'; object-src 'none'">
        <style>html,body,iframe{width:100%;height:100%;margin:0;border:0;background:transparent}</style></head>
        <body><iframe sandbox="allow-scripts allow-same-origin" src="\(origin.indexURL.absoluteString)"></iframe></body></html>
        """
    }

    private static let schemeSource = "\(AphroditeAppOrigin.scheme):"
}
