import DesktopPetSkinKit
/// Wraps a validated skin fragment in a locked-down document. Host CSS pauses or stops motion
/// and keeps the page transparent. The CSP blocks scripts and every network load.
enum DesktopPetSkinDocument {
    static let contentSecurityPolicy = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; media-src 'none'; script-src 'none'; base-uri 'none'; form-action 'none'"

    static func make(markup: String, attributes: [DesktopPetSkinAttributes.Attribute]) -> String {
        let htmlAttributes = attributes.map { "\($0.name)=\"\($0.value)\"" }.joined(separator: " ")
        return """
        <!doctype html>
        <html \(htmlAttributes)>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>
        html, body { margin: 0; padding: 0; background: transparent !important; overflow: hidden; \
        width: \(DesktopPetSkinContract.canvasWidth)px; height: \(DesktopPetSkinContract.canvasHeight)px; \
        -webkit-user-select: none; cursor: default; }
        [data-paused="true"] *, [data-paused="true"] *::before, [data-paused="true"] *::after { animation-play-state: paused !important; }
        [data-reduce-motion="true"] *, [data-reduce-motion="true"] *::before, [data-reduce-motion="true"] *::after { animation: none !important; transition: none !important; }
        </style>
        </head>
        <body>
        \(markup)
        </body>
        </html>
        """
    }
}
