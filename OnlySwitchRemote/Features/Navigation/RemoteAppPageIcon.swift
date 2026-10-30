import SwiftUI

/// The tab icon for a page, sized so brand logos match the SF Symbol tabs.
struct RemoteAppPageIcon: View {
    let page: RemoteAppPage

    var body: some View {
        if let symbol = page.tabSymbol {
            Image(systemName: symbol)
        } else if let imageName = page.tabImageName {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
    }
}
