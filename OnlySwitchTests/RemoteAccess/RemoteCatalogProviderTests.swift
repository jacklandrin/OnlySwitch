import RemoteCore
import Switches
import XCTest
@testable import OnlySwitch

@MainActor
final class RemoteCatalogProviderTests: XCTestCase {
    func testCatalogIncludesUnavailableBuiltInsAndAllInstalledContent() async throws {
        let evolutionID = UUID()
        let provider = RemoteCatalogProvider(
            builtIns: { [.darkMode, .airPods] },
            makeBuiltIn: { FakeSwitch(type: $0, visible: $0 == .darkMode) },
            shortcutNames: { ["Focus Setup", "Deploy"] },
            evolutions: {
                [EvolutionItem(
                    id: evolutionID,
                    name: "Deploy Site",
                    controlType: .Button,
                    singleCommand: EvolutionCommand(commandType: .single, commandString: "deploy")
                )]
            }
        )

        let catalog = try await provider.catalog()

        XCTAssertEqual(catalog.count, 5)
        let airPods = catalog[id: .init(kind: .builtIn, value: "512")]
        XCTAssertEqual(airPods?.isAvailable, false)
        XCTAssertEqual(airPods?.unavailableReason, "No compatible AirPods are configured or connected")
        XCTAssertNotNil(catalog[id: .init(kind: .shortcut, value: "Focus Setup")])
        XCTAssertNotNil(catalog[id: .init(kind: .shortcut, value: "Deploy")])
        XCTAssertNotNil(catalog[id: .init(kind: .evolution, value: evolutionID.uuidString)])
    }

    func testCatalogMapsBehaviorIconsAndDestructiveFlags() async throws {
        let provider = RemoteCatalogProvider(
            builtIns: { [.mute, .emptyTrash, .xcodeCache] },
            makeBuiltIn: { FakeSwitch(type: $0, visible: true) },
            shortcutNames: { [] },
            evolutions: { [] }
        )

        let catalog = try await provider.catalog()

        XCTAssertEqual(catalog[id: .init(kind: .builtIn, value: "8")]?.behavior, .switch)
        XCTAssertEqual(
            catalog[id: .init(kind: .builtIn, value: "8")]?.icon,
            .systemSymbol("speaker.wave.2.circle")
        )
        XCTAssertEqual(catalog[id: .init(kind: .builtIn, value: "16384")]?.behavior, .button)
        XCTAssertEqual(catalog[id: .init(kind: .builtIn, value: "16384")]?.isDestructive, true)
        XCTAssertEqual(catalog[id: .init(kind: .builtIn, value: "2048")]?.isDestructive, true)
    }

    func testIncompleteEvolutionIsIncludedButUnavailable() async throws {
        let evolution = EvolutionItem(id: UUID(), name: "Incomplete", controlType: .Switch)
        let provider = RemoteCatalogProvider(
            builtIns: { [] },
            makeBuiltIn: { FakeSwitch(type: $0, visible: true) },
            shortcutNames: { [] },
            evolutions: { [evolution] }
        )

        let descriptor = try XCTUnwrap(try await provider.catalog().first)

        XCTAssertFalse(descriptor.isAvailable)
        XCTAssertEqual(descriptor.unavailableReason, "This Evolution is missing its on, off, or status command")
    }

    func testStatusNormalizesSecondaryInformation() async throws {
        let control = FakeSwitch(type: .darkMode, visible: true)
        control.status = true
        control.info = "  Active display  "
        let provider = RemoteCatalogProvider(
            builtIns: { [.darkMode] },
            makeBuiltIn: { _ in control },
            shortcutNames: { [] },
            evolutions: { [] },
            now: { Date(timeIntervalSince1970: 123) }
        )

        let status = try await provider.status(.init(kind: .builtIn, value: "2"), 7)

        XCTAssertEqual(status.isOn, true)
        XCTAssertEqual(status.secondaryInformation, "Active display")
        XCTAssertEqual(status.revision, 7)
        XCTAssertEqual(status.updatedAt, Date(timeIntervalSince1970: 123))
    }

    func testEvolutionStatusUsesItsInstalledStatusCommand() async throws {
        let evolution = EvolutionItem(
            id: UUID(),
            name: "Service",
            controlType: .Switch,
            onCommand: EvolutionCommand(commandType: .on, commandString: "start"),
            offCommand: EvolutionCommand(commandType: .off, commandString: "stop"),
            statusCommand: EvolutionCommand(
                commandType: .status,
                commandString: "status",
                trueCondition: "running"
            )
        )
        let provider = RemoteCatalogProvider(
            builtIns: { [] },
            makeBuiltIn: { FakeSwitch(type: $0, visible: true) },
            shortcutNames: { [] },
            evolutions: { [evolution] },
            evolutionStatus: { _ in true }
        )

        let status = try await provider.status(
            .init(kind: .evolution, value: evolution.id.uuidString),
            4
        )

        XCTAssertEqual(status.isOn, true)
        XCTAssertEqual(status.revision, 4)
    }
}
