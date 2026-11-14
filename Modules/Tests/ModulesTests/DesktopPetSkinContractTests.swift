import DesktopPetSkinKit
import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetSkinContractTests {
    @Test func requiredStatesMatchTheNativeAnimationContract() {
        #expect(DesktopPetSkinContract.requiredStates == DesktopPetAnimation.allCases.map(\.rawValue))
    }

    @Test func skinRoundTripsThroughJSON() throws {
        let skin = DesktopPetSkin(
            id: UUID(), name: "Cat", summary: "a cat", createdAt: Date(timeIntervalSinceReferenceDate: 1),
            contractVersion: DesktopPetSkinContract.version, markup: "<div id=\"pet\"></div>"
        )
        let decoded = try JSONDecoder().decode(DesktopPetSkin.self, from: JSONEncoder().encode(skin))
        #expect(decoded == skin)
    }
}
