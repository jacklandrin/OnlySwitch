import Testing
@testable import Switches

struct SwitchLegacyIdentifierCompatibilityTests {
    @Test(arguments: [
        (SwitchType.hiddeDesktop, UInt64(1)),
        (SwitchType.emptyTrash, UInt64(16_384)),
        (SwitchType.reverseScrollDirection, UInt64(2_199_023_255_552)),
    ])
    func legacyNumericIdentifiersRemainPubliclyStable(_ value: (SwitchType, UInt64)) {
        #expect(value.0.legacyIdentifier == value.1)
        #expect(SwitchType(legacyIdentifier: value.1) == value.0)
        #expect(String(value.0.legacyIdentifier) == String(value.1))
    }
}
