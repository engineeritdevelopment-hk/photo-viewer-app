import XCTest
@testable import Photo_Viewer

@MainActor
final class AppUpdateModelTests: XCTestCase {
    private var savedCheckDate: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedCheckDate = UserDefaults.standard.object(forKey: "lastAutomaticUpdateCheckDate")
    }

    override func tearDownWithError() throws {
        if let savedCheckDate {
            UserDefaults.standard.set(savedCheckDate, forKey: "lastAutomaticUpdateCheckDate")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastAutomaticUpdateCheckDate")
        }
        try super.tearDownWithError()
    }

    func testRemindLaterHidesTheOfferUntilTheNextLaunch() async throws {
        let model = AppUpdateModel(updateChecker: stubChecker(tag: "v9.9.9", status: 200))
        await model.checkForUpdates(userInitiated: false)
        let offer = try XCTUnwrap(model.offerToPresent)

        model.remindLater(offer: offer)
        XCTAssertNil(model.offerToPresent)

        await model.checkForUpdates(userInitiated: false)
        XCTAssertNil(model.offerToPresent)

        await model.checkForUpdates(userInitiated: true)
        XCTAssertEqual(model.offerToPresent?.versionLabel, "v9.9.9")
    }

    func testManualCheckReportsUpToDateAndBadResponses() async {
        let current = AppUpdateModel(updateChecker: stubChecker(tag: "v0.0.1", status: 200))
        await current.checkForUpdates(userInitiated: true)
        XCTAssertNil(current.offerToPresent)
        XCTAssertTrue(current.manualCheckAlert?.message.contains("up to date") == true)

        let failed = AppUpdateModel(updateChecker: stubChecker(tag: "v9.9.9", status: 500))
        await failed.checkForUpdates(userInitiated: true)
        XCTAssertNil(failed.offerToPresent)
        XCTAssertTrue(failed.manualCheckAlert?.message.contains("Could not read release") == true)

        let quiet = AppUpdateModel(updateChecker: stubChecker(tag: "v9.9.9", status: 500))
        await quiet.checkForUpdates(userInitiated: false)
        XCTAssertNil(quiet.manualCheckAlert)
        XCTAssertNil(quiet.offerToPresent)
    }

    func testPeriodicCheckSkipsWhenOneJustRan() async {
        AppPreferences.recordAutomaticUpdateCheck()
        let model = AppUpdateModel(updateChecker: stubChecker(tag: "v9.9.9", status: 200))
        await model.performPeriodicCheckIfNeeded()
        XCTAssertNil(model.offerToPresent)
        XCTAssertFalse(model.isChecking)
    }

    func testLaunchCheckRecordsTheAutomaticCheck() async {
        UserDefaults.standard.removeObject(forKey: "lastAutomaticUpdateCheckDate")
        XCTAssertTrue(AppPreferences.shouldRunAutomaticUpdateCheck())
        let model = AppUpdateModel(updateChecker: stubChecker(tag: "v0.0.1", status: 200))
        await model.performCheckOnLaunch()
        XCTAssertFalse(AppPreferences.shouldRunAutomaticUpdateCheck())
    }

    func testInstallWithoutZipFailsBeforeDownload() async {
        let model = AppUpdateModel()
        let offer = ReleaseUpdateOffer(
            version: AppVersion.parse("9.0.0")!,
            versionLabel: "v9.0.0",
            title: "Nine",
            releaseNotes: "",
            releasePageURL: URL(string: "https://example.com/release")!,
            downloadURL: nil
        )
        await model.startAutomaticInstall(offer: offer)
        guard case .failed(let message) = model.installPhase else {
            return XCTFail("expected a failed install, got \(model.installPhase)")
        }
        XCTAssertTrue(message.contains(".zip"))
    }

    func testCheckDoesNotStartWhileAnInstallIsRunning() async {
        let model = AppUpdateModel(updateChecker: stubChecker(tag: "v9.9.9", status: 200))
        model.installPhase = .downloading
        await model.checkForUpdates(userInitiated: true)
        XCTAssertNil(model.offerToPresent)
        XCTAssertFalse(model.isChecking)
    }

    private func stubChecker(tag: String, status: Int) -> ReleaseUpdateChecker {
        UpdateURLStub.response = (releaseJSON(tag: tag), status)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLStub.self]
        return ReleaseUpdateChecker(session: URLSession(configuration: configuration))
    }

    private func releaseJSON(tag: String) -> Data {
        let json = """
        {"tag_name":"\(tag)","html_url":"https://example.com/r","name":"Release","body":"notes","draft":false,"prerelease":false,"assets":[]}
        """
        return Data(json.utf8)
    }
}

private final class UpdateURLStub: URLProtocol {
    static var response: (Data, Int) = (Data(), 500)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (data, status) = Self.response
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
