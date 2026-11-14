import CoreGraphics

enum BrowserUserAgent {
    /// iPhone Safari, so sites serve their narrow layout in the menu-bar panel.
    static let mobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Respect a site's own viewport, adding the responsive default only to older pages without one.
    /// The isolated world exposes no native messaging surface to page scripts.
    static let viewportScript = """
    (() => {
        if (!document.head || document.querySelector('meta[name="viewport" i]')) return;
        const viewport = document.createElement('meta');
        viewport.name = 'viewport';
        viewport.content = 'width=device-width, initial-scale=1';
        document.head.appendChild(viewport);
    })();
    """

}
