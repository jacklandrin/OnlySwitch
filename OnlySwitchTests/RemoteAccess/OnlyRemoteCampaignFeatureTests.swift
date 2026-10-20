import ComposableArchitecture
import Testing
@testable import OnlySwitch

@MainActor
struct OnlyRemoteCampaignFeatureTests {
    private let manifest = OnlyRemoteCampaignManifest(date: "2026-10-20", file: "2026-10-20.html")
    private let html = "<!doctype html><html><body>Campaign</body></html>"

    @Test
    func launchLoadsUnseenCampaignWithoutPresentingOrAcknowledgingIt() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        let store = makeStore(recorder)
        let document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)

        await store.send(.launch) {
            $0.hasChecked = true
            $0.isLoading = true
        }
        await store.receive(.campaignLoaded(document)) {
            $0.isLoading = false
            $0.document = document
        }
        await store.finish()

        #expect(store.state.isPresented == false)
        #expect(await recorder.acknowledgedVersions.isEmpty)
        #expect(await recorder.htmlFetchCount == 1)
    }

    @Test(arguments: ["2026-10-20", "2026-10-21"])
    func alreadySeenOrOlderCampaignDoesNotFetchHTML(acknowledgedDate: String) async {
        let recorder = OnlyRemoteCampaignRecorder(
            manifest: manifest, html: html, acknowledgedVersion: acknowledgedDate
        )
        let store = makeStore(recorder)

        await store.send(.launch) {
            $0.hasChecked = true
            $0.isLoading = true
        }
        await store.receive(.campaignLoaded(nil)) { $0.isLoading = false }
        await store.finish()

        #expect(store.state.document == nil)
        #expect(store.state.isPresented == false)
        #expect(await recorder.htmlFetchCount == 0)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test(arguments: [OnlyRemoteCampaignRecorder.Failure.manifest, .html])
    func requestFailureIsSilentAndDoesNotAcknowledge(failure: OnlyRemoteCampaignRecorder.Failure) async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html, failure: failure)
        let store = makeStore(recorder)

        await store.send(.launch) {
            $0.hasChecked = true
            $0.isLoading = true
        }
        await store.receive(.campaignLoaded(nil)) { $0.isLoading = false }
        await store.finish()

        #expect(store.state.document == nil)
        #expect(store.state.isPresented == false)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func invalidManifestDoesNotFetchOrPresentHTML() async {
        let invalid = OnlyRemoteCampaignManifest(date: "2026-02-30", file: "2026-02-30.html")
        let recorder = OnlyRemoteCampaignRecorder(manifest: invalid, html: html)
        let store = makeStore(recorder)

        await store.send(.launch) {
            $0.hasChecked = true
            $0.isLoading = true
        }
        await store.receive(.campaignLoaded(nil)) { $0.isLoading = false }
        await store.finish()

        #expect(await recorder.htmlFetchCount == 0)
        #expect(store.state.isPresented == false)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func successfulPageLoadPresentsAndAcknowledgesTheDocumentDateOnlyOnce() async {
        let document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.document = document
        let store = makeStore(recorder, state: state)

        await store.send(.pageLoaded(manifest.date)) { $0.isPresented = true }
        await store.finish()
        await store.send(.pageLoaded(manifest.date))
        await store.finish()

        #expect(await recorder.acknowledgedVersions == [manifest.date])
    }

    @Test
    func failedPageLoadDiscardsDocumentWithoutAcknowledging() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)
        let store = makeStore(recorder, state: state)

        await store.send(.pageFailed(manifest.date)) { $0.document = nil }
        await store.send(.pageLoaded(manifest.date))
        await store.finish()

        #expect(store.state.isPresented == false)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func dismissHidesAndClearsDocumentWithoutAcknowledgingAgain() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)
        state.isPresented = true
        let store = makeStore(recorder, state: state)

        await store.send(.dismissTapped) {
            $0.isPresented = false
            $0.document = nil
        }
        await store.send(.dismissTapped)
        await store.send(.pageLoaded(manifest.date))
        await store.finish()

        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func duplicateLaunchWhileLoadingDoesNotStartAnotherRequest() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.isLoading = true
        let store = makeStore(recorder, state: state)

        await store.send(.launch)
        await store.finish()

        #expect(await recorder.manifestFetchCount == 0)
    }

    @Test
    func completedLaunchAttemptIsNotRepeatedDuringTheSameSession() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.hasChecked = true
        let store = makeStore(recorder, state: state)

        await store.send(.launch)
        await store.finish()

        #expect(await recorder.manifestFetchCount == 0)
    }

    @Test
    func launchDoesNotReplaceAnAlreadyPreparedDocument() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)
        let store = makeStore(recorder, state: state)

        await store.send(.launch)
        await store.finish()

        #expect(await recorder.manifestFetchCount == 0)
    }

    @Test
    func stalePageCallbacksDoNotPresentOrClearCurrentDocument() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)
        let store = makeStore(recorder, state: state)

        await store.send(.pageLoaded("2026-10-19"))
        await store.send(.pageFailed("2026-10-19"))
        await store.finish()

        #expect(store.state.document?.manifest == manifest)
        #expect(store.state.isPresented == false)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func downloadLinkShowsNativeQRCodeAndKeepsCampaignPresented() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        let document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.document = document
        state.isPresented = true
        let store = makeStore(recorder, state: state)

        await store.send(.showQRCodeTapped)
        await store.finish()

        #expect(await recorder.qrCodePresentationCount == 1)
        #expect(await recorder.acknowledgedVersions.isEmpty)
        #expect(store.state.isPresented)
        #expect(store.state.document == document)
    }

    @Test
    func downloadLinkDoesNotShowQRCodeBeforePresentationOrAfterDismissal() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)
        let store = makeStore(recorder, state: state)

        await store.send(.showQRCodeTapped)
        await store.send(.dismissTapped) { $0.document = nil }
        await store.send(.showQRCodeTapped)
        await store.finish()

        #expect(await recorder.qrCodePresentationCount == 0)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test(arguments: ["2026-10-20", "2026-10-21"])
    func forcedPresentationLoadsLatestHTMLDespiteAcknowledgedDate(acknowledgedDate: String) async {
        let recorder = OnlyRemoteCampaignRecorder(
            manifest: manifest, html: html, acknowledgedVersion: acknowledgedDate
        )
        let store = makeStore(recorder, forcePresentation: true)
        let document = OnlyRemoteCampaignDocument(manifest: manifest, html: html)

        await store.send(.launch) {
            $0.hasChecked = true
            $0.isLoading = true
        }
        await store.receive(.campaignLoaded(document)) {
            $0.isLoading = false
            $0.document = document
        }
        await store.finish()

        #expect(await recorder.htmlFetchCount == 1)
        #expect(await recorder.acknowledgedVersions.isEmpty)
        #expect(store.state.isPresented == false)

        await store.send(.pageLoaded(manifest.date)) { $0.isPresented = true }
        await store.finish()

        #expect(await recorder.acknowledgedVersions.isEmpty,
                "A forced debug preview must preserve the release acknowledgement date.")
    }

    @Test(arguments: [OnlyRemoteCampaignRecorder.Failure.manifest, .html])
    func forcedPresentationRequestFailureRemainsSilent(failure: OnlyRemoteCampaignRecorder.Failure) async {
        let recorder = OnlyRemoteCampaignRecorder(
            manifest: manifest, html: html, acknowledgedVersion: manifest.date, failure: failure
        )
        let store = makeStore(recorder, forcePresentation: true)

        await store.send(.launch) {
            $0.hasChecked = true
            $0.isLoading = true
        }
        await store.receive(.campaignLoaded(nil)) { $0.isLoading = false }
        await store.finish()

        #expect(store.state.document == nil)
        #expect(store.state.isPresented == false)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func forcedPresentationStillChecksOnlyOncePerSession() async {
        let recorder = OnlyRemoteCampaignRecorder(manifest: manifest, html: html)
        var state = OnlyRemoteCampaignFeature.State()
        state.hasChecked = true
        let store = makeStore(recorder, state: state, forcePresentation: true)

        await store.send(.launch)
        await store.finish()

        #expect(await recorder.manifestFetchCount == 0)
    }

    private func makeStore(
        _ recorder: OnlyRemoteCampaignRecorder,
        state: OnlyRemoteCampaignFeature.State = .init(),
        forcePresentation: Bool = false
    ) -> TestStore<OnlyRemoteCampaignFeature.State, OnlyRemoteCampaignFeature.Action> {
        TestStore(initialState: state) {
            OnlyRemoteCampaignFeature(forcePresentation: forcePresentation)
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }
    }
}

struct OnlyRemoteCampaignManifestTests {
    @Test(arguments: ["2026-10-20", "2024-02-29", "2000-02-29"])
    func acceptsStrictGregorianDates(date: String) {
        #expect(OnlyRemoteCampaignManifest(date: date, file: "\(date).html").isValid)
    }

    @Test(arguments: [
        "2026-02-29", "1900-02-29", "2026-02-30", "2026-04-31", "2026-00-20",
        "2026-13-20", "2026-10-00", "2026-10-32", "2026-1-20", "26-10-20",
        "2026-10-20T00:00:00Z", "2026-10-20 ", "２０２６-１０-２０", "0000-01-01"
    ])
    func rejectsInvalidOrNonCanonicalDates(date: String) {
        #expect(OnlyRemoteCampaignManifest(date: date, file: "\(date).html").isValid == false)
    }

    @Test(arguments: [
        "../2026-10-20.html", "/2026-10-20.html", "2026-10-19.html", "2026-10-20.HTML",
        "https://example.com/2026-10-20.html", "2026-10-20.html?redirect=true",
        "%2e%2e/2026-10-20.html", "2026-10-20.html#section", "2026-10-20.html/extra"
    ])
    func rejectsFilesOtherThanExactDateFilename(file: String) {
        #expect(OnlyRemoteCampaignManifest(date: "2026-10-20", file: file).isValid == false)
    }
}

actor OnlyRemoteCampaignRecorder {
    enum Failure: Error, Sendable {
        case manifest
        case html
    }

    nonisolated let manifest: OnlyRemoteCampaignManifest
    nonisolated let html: String
    nonisolated let acknowledgedVersion: String?
    nonisolated let failure: Failure?
    private(set) var acknowledgedVersions: [String] = []
    private(set) var manifestFetchCount = 0
    private(set) var htmlFetchCount = 0
    private(set) var qrCodePresentationCount = 0

    init(
        manifest: OnlyRemoteCampaignManifest,
        html: String,
        acknowledgedVersion: String? = nil,
        failure: Failure? = nil
    ) {
        self.manifest = manifest
        self.html = html
        self.acknowledgedVersion = acknowledgedVersion
        self.failure = failure
    }

    nonisolated var client: OnlyRemoteCampaignClient {
        OnlyRemoteCampaignClient(
            fetchLatest: { try await self.fetchLatest() },
            fetchHTML: { _ in try await self.fetchHTML() },
            acknowledgedVersion: { self.acknowledgedVersion },
            markAcknowledged: { version in await self.markAcknowledged(version) },
            showQRCode: { await self.showQRCode() }
        )
    }

    private func fetchLatest() throws -> OnlyRemoteCampaignManifest {
        manifestFetchCount += 1
        if failure == .manifest { throw Failure.manifest }
        return manifest
    }

    private func fetchHTML() throws -> String {
        htmlFetchCount += 1
        if failure == .html { throw Failure.html }
        return html
    }

    private func showQRCode() {
        qrCodePresentationCount += 1
    }

    private func markAcknowledged(_ version: String) {
        acknowledgedVersions.append(version)
    }
}


@MainActor
struct OnlyRemoteCampaignWebViewTests {
    @Test(.timeLimit(.minutes(1)))
    func hiddenWebViewLoadsInitialDocumentAndInjectsAppLanguage() async throws {
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        let webView = OnlyRemoteCampaignView(
            language: "zh-Hans",
            onLoaded: {
                continuation.yield(true)
                continuation.finish()
            },
            onFailed: {
                continuation.yield(false)
                continuation.finish()
            },
            onDownload: { Issue.record("Rendering campaign content must not invoke the download action.") }
        )
        webView.loadHTMLString(
            """
            <!doctype html><html><head><meta charset="utf-8"></head><body>
            <script>
            window.setCampaignLanguage = function(language) {
                document.documentElement.lang = language;
            };
            window.setCampaignLanguage(window.onlySwitchLanguage);
            </script>
            </body></html>
            """,
            baseURL: nil
        )
        var iterator = events.makeAsyncIterator()
        let loaded = await iterator.next()
        try #require(loaded == true, "The hidden initial about:blank document should finish loading.")
        let language: String? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.lang") { value, _ in
                continuation.resume(returning: value as? String)
            }
        }

        #expect(language == "zh-Hans")
        #expect(webView.window == nil)
    }
}
