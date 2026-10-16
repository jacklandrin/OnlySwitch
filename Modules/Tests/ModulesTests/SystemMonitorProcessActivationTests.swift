import Foundation
import ComposableArchitecture
import RemoteCore
import SystemMonitor
import Testing

struct SystemMonitorProcessActivationTests {
    @Test func legacyProcessJSONDecodesWithoutActivationTarget() throws {
        let json = Data(#"""
        {
          "pid": 42,
          "name": "Legacy Helper",
          "cpuUsage": { "available": { "_0": 0.25 } },
          "memoryBytes": { "available": { "_0": 4096 } },
          "downloadBytesPerSecond": { "unavailable": {} },
          "uploadBytesPerSecond": { "unavailable": {} }
        }
        """#.utf8)

        let process = try JSONDecoder().decode(SystemMonitorProcess.self, from: json)

        #expect(process.pid == 42)
        #expect(process.name == "Legacy Helper")
        #expect(process.activationTarget == nil)
    }

    @Test func helperActivationTargetRoundTripsWithExactIntegerIdentity() throws {
        let target = SystemMonitorProcessActivationTarget(
            sampledProcess: .init(pid: 41, startTimeMicroseconds: 1_234_567_890_123_456),
            owningApplication: .init(pid: 84, startTimeMicroseconds: 9_876_543_210_654_321)
        )
        let process = SystemMonitorProcess(pid: 41, name: "Helper", activationTarget: target)

        let decoded = try JSONDecoder().decode(
            SystemMonitorProcess.self,
            from: JSONEncoder().encode(process)
        )

        #expect(decoded == process)
        #expect(decoded.activationTarget?.sampledProcess.pid == 41)
        #expect(decoded.activationTarget?.owningApplication.pid == 84)
        #expect(decoded.activationTarget?.sampledProcess.startTimeMicroseconds == 1_234_567_890_123_456)
        #expect(decoded.activationTarget?.owningApplication.startTimeMicroseconds == 9_876_543_210_654_321)
    }

    @Test(arguments: [
        (seconds: Int64(0), microseconds: Int32(0), expected: UInt64(0)),
        (seconds: Int64(12), microseconds: Int32(345_678), expected: UInt64(12_345_678)),
        (seconds: Int64(-1), microseconds: Int32(0), expected: nil),
        (seconds: Int64(1), microseconds: Int32(-1), expected: nil),
        (seconds: Int64(1), microseconds: Int32(1_000_000), expected: nil),
        (seconds: Int64.max, microseconds: Int32(0), expected: nil),
    ])
    func integerStartTimeConversion(
        _ sample: (seconds: Int64, microseconds: Int32, expected: UInt64?)
    ) {
        #expect(
            SystemMonitorProcessOwnershipResolver.startTimeMicroseconds(
                seconds: sample.seconds,
                microseconds: sample.microseconds
            ) == sample.expected
        )
    }

    @MainActor
    @Test func directRegularApplicationIsItsOwnOwner() {
        let source = identity(10, 100)
        let resolver = makeResolver(
            identities: [10: source],
            regularApplications: [10: source]
        )

        #expect(resolver.activationTarget(for: source) == .init(
            sampledProcess: source,
            owningApplication: source
        ))
    }

    @MainActor
    @Test func ownershipRejectsSampledIdentityAfterPIDReuse() {
        let sampled = identity(10, 100)
        let reused = identity(10, 101)
        let resolver = makeResolver(
            identities: [10: reused],
            regularApplications: [10: reused]
        )

        #expect(resolver.activationTarget(for: sampled) == nil)
    }

    @MainActor
    @Test func responsibleApplicationTakesPrecedenceOverParent() {
        let source = identity(10, 100)
        let responsible = identity(20, 200)
        let parent = identity(30, 300)
        let resolver = makeResolver(
            identities: [10: source, 20: responsible, 30: parent],
            regularApplications: [20: responsible, 30: parent],
            responsiblePIDs: [10: 20],
            parentPIDs: [10: 30]
        )

        #expect(resolver.activationTarget(for: source)?.owningApplication == responsible)
    }

    @MainActor
    @Test func parentApplicationIsFoundWithinFourHops() {
        let source = identity(10, 100)
        let owner = identity(14, 140)
        let resolver = makeResolver(
            identities: [10: source, 14: owner],
            regularApplications: [14: owner],
            parentPIDs: [10: 11, 11: 12, 12: 13, 13: 14]
        )

        #expect(resolver.activationTarget(for: source)?.owningApplication == owner)
    }

    @MainActor
    @Test func fifthParentHopIsRejected() {
        let source = identity(10, 100)
        let owner = identity(15, 150)
        let resolver = makeResolver(
            identities: [10: source, 15: owner],
            regularApplications: [15: owner],
            parentPIDs: [10: 11, 11: 12, 12: 13, 13: 14, 14: 15]
        )

        #expect(resolver.activationTarget(for: source) == nil)
    }

    @MainActor
    @Test func parentCycleAndDaemonAreRejected() {
        let source = identity(10, 100)
        let resolver = makeResolver(
            identities: [10: source],
            parentPIDs: [10: 11, 11: 12, 12: 11]
        )

        #expect(resolver.activationTarget(for: source) == nil)
    }

    @MainActor
    @Test(arguments: ActivationValidationFailure.allCases)
    func activationRequiresCurrentSourceAndRegularOwnerIdentity(
        _ failure: ActivationValidationFailure
    ) {
        let source = identity(10, 100)
        let owner = identity(20, 200)
        let target = SystemMonitorProcessActivationTarget(
            sampledProcess: source,
            owningApplication: owner
        )
        let activations = LockIsolated(0)
        var identities: [Int32: SystemMonitorProcessIdentity] = [10: source, 20: owner]
        var regularApplications: [Int32: SystemMonitorProcessIdentity] = [20: owner]

        switch failure {
        case .sourceExited:
            identities[10] = nil
        case .sourcePIDReused:
            identities[10] = identity(10, 101)
        case .ownerExited:
            identities[20] = nil
            regularApplications[20] = nil
        case .ownerPIDReused:
            identities[20] = identity(20, 201)
            regularApplications[20] = identity(20, 201)
        case .ownerIsNotRegular:
            regularApplications[20] = nil
        case .activationReturnedFalse:
            break
        }

        let resolver = makeResolver(
            identities: identities,
            regularApplications: regularApplications
        )
        let outcome = resolver.activate(target) { _ in
            activations.withValue { $0 += 1 }
            return failure != .activationReturnedFalse
        }

        #expect(outcome == .unavailable)
        #expect(activations.value == (failure == .activationReturnedFalse ? 1 : 0))
    }

    @MainActor
    @Test func validTargetActivatesOwningApplicationExactlyOnce() {
        let source = identity(10, 100)
        let owner = identity(20, 200)
        let activations = LockIsolated<[Int32]>([])
        let resolver = makeResolver(
            identities: [10: source, 20: owner],
            regularApplications: [20: owner]
        )

        let outcome = resolver.activate(.init(
            sampledProcess: source,
            owningApplication: owner
        )) { pid in
            activations.withValue { $0.append(pid) }
            return true
        }

        #expect(outcome == .activated)
        #expect(activations.value == [20])
    }

    @Test func activationLocalizationKeysCoverEverySupportedLocale() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repository.appending(path: "Localization/Localizable.xcstrings")
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let strings = try #require(object["strings"] as? [String: Any])
        let locales = [
            "cs", "de", "en", "es", "fil", "fr", "hr", "it", "ja", "ko",
            "nl", "pl", "pt-BR", "ru", "sk", "so", "tr", "uk", "zh-Hans", "zh-Hant",
        ]
        let keys = [
            "Activate %@",
            "Activates the application for this process",
            "Application unavailable",
            "The application for this process is no longer available.",
        ]

        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "Missing localization key: \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for locale in locales {
                let localization = try #require(
                    localizations[locale] as? [String: Any],
                    "Missing \(locale) translation for \(key)"
                )
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
                let value = try #require(stringUnit["value"] as? String)
                #expect(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            }
        }
    }

    @MainActor
    private func makeResolver(
        identities: [Int32: SystemMonitorProcessIdentity],
        regularApplications: [Int32: SystemMonitorProcessIdentity] = [:],
        responsiblePIDs: [Int32: Int32] = [:],
        parentPIDs: [Int32: Int32] = [:]
    ) -> SystemMonitorProcessOwnershipResolver {
        SystemMonitorProcessOwnershipResolver(
            processIdentity: { identities[$0] },
            regularApplicationIdentity: { regularApplications[$0] },
            responsiblePID: { responsiblePIDs[$0] },
            parentPID: { parentPIDs[$0] }
        )
    }

    private func identity(_ pid: Int32, _ startTimeMicroseconds: UInt64) -> SystemMonitorProcessIdentity {
        .init(pid: pid, startTimeMicroseconds: startTimeMicroseconds)
    }
}

enum ActivationValidationFailure: CaseIterable {
    case sourceExited
    case sourcePIDReused
    case ownerExited
    case ownerPIDReused
    case ownerIsNotRegular
    case activationReturnedFalse

}
