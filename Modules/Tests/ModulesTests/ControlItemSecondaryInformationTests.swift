import AppKit
import Testing
@testable import OnlyControl

struct ControlItemSecondaryInformationTests {
    @Test func emptyInformationHasNoSubtitle() {
        #expect(ControlItemSecondaryInformation.subtitle(info: "   ", isAirPods: false) == nil)
    }

    @Test func ordinaryInformationIsTrimmed() {
        #expect(
            ControlItemSecondaryInformation.subtitle(
                info: "  gpt-5.6-sol  ",
                isAirPods: false
            ) == "gpt-5.6-sol"
        )
    }

    @Test func airPodsBatteryInformationUsesCompactLabels() {
        #expect(
            ControlItemSecondaryInformation.subtitle(
                info: "46 100 100",
                isAirPods: true
            ) == "C 46% · L 100% · R 100%"
        )
    }

    @Test func unavailableAirPodsBatteryValuesAreOmitted() {
        #expect(
            ControlItemSecondaryInformation.subtitle(
                info: "-1 82 -1",
                isAirPods: true
            ) == "L 82%"
        )
    }

    @Test func subtitleParticipatesInViewStateEquality() {
        let iconData = NSImage(systemSymbolName: "gear").tiffRepresentation!
        let first = ControlItemViewState(
            id: "agent",
            title: "Only Agent",
            subtitle: "gpt-5.6-sol",
            iconData: iconData,
            controlType: .Button
        )
        let second = ControlItemViewState(
            id: "agent",
            title: "Only Agent",
            subtitle: "gpt-5.5",
            iconData: iconData,
            controlType: .Button
        )

        #expect(first != second)
    }
}
