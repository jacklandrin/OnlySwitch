import Authenticator
import SwiftUI

struct AuthenticatorControlPopover: View {
    let onCodeCopied: () -> Void

    var body: some View {
        AuthenticatorPanelView(onCodeCopied: onCodeCopied)
        .frame(width: 360)
    }
}
