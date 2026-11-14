import DesktopPetSkinKit

/// A minimal skin that passes `DesktopPetSkinValidator`, shared by the skin library and generation tests.
enum DesktopPetSkinFixture {
    static let valid: String = {
        let rules = DesktopPetSkinContract.requiredStates.map { "[data-state=\"\($0)\"] #pet{}" }.joined()
        return "<style>\(rules)</style><div id=\"pet\"></div>"
    }()
}
