import XCTest
import CoreGraphics
@testable import MonitorCore

final class LayoutTests: XCTestCase {
    func testChangingMainPreservesRelativePosition() {
        let settings = fixtures().map(DisplaySetting.init)
        let result = Layout.makingMain(2, in: settings)
        XCTAssertEqual(result[1].origin, .zero)
        XCTAssertEqual(result[0].origin, CGPoint(x: -1920, y: -100))
        XCTAssertNoThrow(try Layout.validate(result))
    }
    func testSnappingTouchesNeighborEdge() {
        let result = Layout.snapped(CGRect(x: 1915, y: 3, width: 1440, height: 900),
                                    to: [CGRect(x: 0, y: 0, width: 1920, height: 1080)], threshold: 20)
        XCTAssertEqual(result, CGPoint(x: 1920, y: 0))
    }
    func testNoDistantSnapping() {
        let result = Layout.snapped(CGRect(x: 1915, y: 5000, width: 1440, height: 900),
                                    to: [CGRect(x: 0, y: 0, width: 1920, height: 1080)], threshold: 20)
        XCTAssertEqual(result, CGPoint(x: 1915, y: 5000))
    }
    func testRejectsMirrorCycleAndMissingTarget() {
        var settings = fixtures().map(DisplaySetting.init)
        settings[0].mirror = 2; settings[1].mirror = 1
        XCTAssertThrowsError(try Layout.validate(settings))
        settings[0].mirror = 0; settings[1].mirror = 99
        XCTAssertThrowsError(try Layout.validate(settings))
    }
    func testRejectsInvalidOriginAndMissingMain() {
        var settings = fixtures().map(DisplaySetting.init)
        settings[0].origin.x = .nan
        XCTAssertThrowsError(try Layout.validate(settings))
        settings[0].origin = CGPoint(x: 500, y: 500)
        XCTAssertThrowsError(try Layout.validate(settings))
    }
    func testHiDPIModesDoNotCollapseWithLowResolution() {
        let display = fixtures()[0]
        XCTAssertEqual(display.resolutions.count, 2)
        XCTAssertTrue(display.modes[0].hiDPI)
        XCTAssertFalse(display.modes[1].hiDPI)
    }
    func testSettingsRoundTrip() throws {
        let settings = fixtures().map(DisplaySetting.init)
        XCTAssertEqual(settings, try JSONDecoder().decode([DisplaySetting].self, from: JSONEncoder().encode(settings)))
    }
}

@MainActor final class SessionTests: XCTestCase {
    func testPreviewIsTemporaryAndConfirmIsPermanent() async throws {
        let backend = FakeDriver()
        let transaction = ConfigurationSession(backend: backend)
        try await transaction.preview(Layout.makingMain(2, in: backend.items.map(DisplaySetting.init)))
        XCTAssertEqual(backend.permanentFlags, [false])
        XCTAssertNotNil(transaction.original)
        XCTAssertFalse(transaction.expired(at: Date()))
        XCTAssertTrue(transaction.expired(at: Date().addingTimeInterval(21)))
        try await transaction.confirm()
        XCTAssertEqual(backend.permanentFlags, [false, true])
        XCTAssertNil(transaction.original)
    }
    func testRevertRestoresOriginal() async throws {
        let backend = FakeDriver(), original = fixtures().map(DisplaySetting.init)
        let transaction = ConfigurationSession(backend: backend)
        try await transaction.preview(Layout.makingMain(2, in: original))
        try await transaction.revert()
        XCTAssertEqual(backend.requests.last, original)
        XCTAssertNil(transaction.deadline)
    }
    func testFailedApplyRollsBack() async {
        let backend = FakeDriver(); backend.failCalls = [1]
        let transaction = ConfigurationSession(backend: backend)
        do { try await transaction.preview(backend.items.map(DisplaySetting.init)); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(backend.requests.count, 2)
        XCTAssertNil(transaction.original)
    }
    func testFailedRollbackKeepsSnapshotForRetry() async throws {
        let backend = FakeDriver(); backend.failCalls = [1, 2]
        let transaction = ConfigurationSession(backend: backend)
        do { try await transaction.preview(backend.items.map(DisplaySetting.init)); XCTFail("Expected failure") } catch {}
        XCTAssertNotNil(transaction.original)
        try await transaction.revert()
        XCTAssertNil(transaction.original)
    }
    func testFailedCommitKeepsRollbackAvailable() async throws {
        let backend = FakeDriver(); backend.failCalls = [2]
        let transaction = ConfigurationSession(backend: backend)
        try await transaction.preview(backend.items.map(DisplaySetting.init))
        do { try await transaction.confirm(); XCTFail("Expected failure") } catch {}
        XCTAssertNotNil(transaction.original)
        try await transaction.revert()
        XCTAssertNil(transaction.original)
    }
    func testDisconnectedDisplayIsNotRestored() async throws {
        let backend = FakeDriver()
        let session = ConfigurationSession(backend: backend)
        try await session.preview(backend.items.map(DisplaySetting.init))
        backend.items.removeLast()
        try await session.revert()
        XCTAssertEqual(backend.requests.last?.map(\.id), [1])
    }
    func testSecondPreviewDoesNotReplaceOriginal() async throws {
        let backend = FakeDriver()
        let session = ConfigurationSession(backend: backend)
        let original = backend.items.map(DisplaySetting.init)
        try await session.preview(original)
        do { try await session.preview(Layout.makingMain(2, in: original)); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(session.original, original)
        XCTAssertEqual(backend.requests.count, 1)
    }
}

@MainActor private final class FakeDriver: DisplayConfiguring {
    var items = fixtures()
    var requests: [[DisplaySetting]] = []
    var permanentFlags: [Bool] = []
    var failCalls: Set<Int> = []
    func displays() -> [DisplayInfo] { items }
    func apply(_ settings: [DisplaySetting], permanently: Bool) async throws {
        requests.append(settings); permanentFlags.append(permanently)
        if failCalls.contains(requests.count) { throw MonitorError.message("Simulated hardware failure") }
        items = items.map { display in
            guard let setting = settings.first(where: { $0.id == display.id }) else { return display }
            return DisplayInfo(id: display.id, identity: display.identity, name: display.name, builtIn: display.builtIn,
                               main: setting.origin == .zero, bounds: CGRect(origin: setting.origin, size: display.bounds.size),
                               mirror: setting.mirror, current: setting.mode, modes: display.modes)
        }
    }
}
private func fixtures() -> [DisplayInfo] {
    let high = DisplayMode(id: 1, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, hz: 60)
    let low = DisplayMode(id: 2, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, hz: 60)
    return [DisplayInfo(id: 1, identity: "physical-a", name: "A", builtIn: true, main: true,
                        bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), current: high, modes: [high, low]),
            DisplayInfo(id: 2, identity: "physical-b", name: "B", builtIn: false, main: false,
                        bounds: CGRect(x: 1920, y: 100, width: 1920, height: 1080), current: low, modes: [low])]
}
