#if os(macOS)
import Switches
import Testing

struct TailscaleSwitchIdentityTests {
    @Test func tailscaleGetsANewStableIdentifierWithoutReusingHistory() {
        #expect(SwitchType.tailscale.legacyIdentifier == 281_474_976_710_656)
        #expect(SwitchType(legacyIdentifier: 281_474_976_710_656) == .tailscale)
        #expect(SwitchType.tailscale.barInfo().controlType == .Switch)
        #expect(SwitchType.allCases.filter { $0.legacyIdentifier == SwitchType.tailscale.legacyIdentifier }.count == 1)
    }
}
#endif
