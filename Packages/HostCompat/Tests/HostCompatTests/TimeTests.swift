import XCTest
@testable import HostCompat

final class HostCompatTests: XCTestCase {
    func testDurationArithmetic() {
        XCTAssertEqual(HostDuration.seconds(2) + .milliseconds(500), .milliseconds(2500))
        XCTAssertEqual(HostDuration.seconds(1.5), .milliseconds(1500))
        XCTAssertLessThan(HostDuration.milliseconds(999), .seconds(1))
        var remaining = HostDuration.seconds(10)
        remaining -= .seconds(4)
        XCTAssertEqual(remaining, .seconds(6))
        XCTAssertEqual(HostDuration.seconds(3).components.seconds, 3)
    }

    func testClocks() async throws {
        let start = HostContinuousClock.now
        try await Task.hostSleep(for: .milliseconds(30))
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(25))
        let deadline = HostSuspendingClock.now + .milliseconds(20)
        try await HostSuspendingClock().sleep(until: deadline)
        XCTAssertGreaterThanOrEqual(HostSuspendingClock.now, deadline)
    }
}
