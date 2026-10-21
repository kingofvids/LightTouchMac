import Foundation

/// Where a clock reads its time. Both are monotonic.
public protocol HostClockSource: Sendable {
    static func nanoseconds() -> UInt64
}

/// Keeps counting while the Mac sleeps (what `ContinuousClock` does).
public enum HostContinuousSource: HostClockSource {
    public static func nanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }
}

/// Stops while the Mac sleeps (what `SuspendingClock` does).
public enum HostSuspendingSource: HostClockSource {
    public static func nanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
}

public typealias HostContinuousClock = HostClock<HostContinuousSource>
public typealias HostSuspendingClock = HostClock<HostSuspendingSource>

public struct HostInstant<Source: HostClockSource>: Sendable, Hashable, Comparable {
    var nanoseconds: UInt64

    public static var now: HostInstant { HostInstant(nanoseconds: Source.nanoseconds()) }

    public func advanced(by duration: HostDuration) -> HostInstant {
        let moved = Int64(clamping: nanoseconds) &+ duration.nanoseconds
        return HostInstant(nanoseconds: moved < 0 ? 0 : UInt64(moved))
    }

    public func duration(to other: HostInstant) -> HostDuration {
        HostDuration(nanoseconds: Int64(clamping: other.nanoseconds) &- Int64(clamping: nanoseconds))
    }

    public static func < (lhs: HostInstant, rhs: HostInstant) -> Bool { lhs.nanoseconds < rhs.nanoseconds }
    public static func + (lhs: HostInstant, rhs: HostDuration) -> HostInstant { lhs.advanced(by: rhs) }
    public static func - (lhs: HostInstant, rhs: HostDuration) -> HostInstant { lhs.advanced(by: -rhs) }
    public static func - (lhs: HostInstant, rhs: HostInstant) -> HostDuration { rhs.duration(to: lhs) }
    public static func += (lhs: inout HostInstant, rhs: HostDuration) { lhs = lhs + rhs }
    public static func -= (lhs: inout HostInstant, rhs: HostDuration) { lhs = lhs - rhs }
}

public struct HostClock<Source: HostClockSource>: Sendable {
    public typealias Instant = HostInstant<Source>

    public init() {}

    public static var now: Instant { Instant.now }
    public var now: Instant { Instant.now }

    /// Suspends until `deadline` (no wait if it has passed); throws if the task is cancelled.
    public func sleep(until deadline: Instant) async throws {
        let remaining = Instant.now.duration(to: deadline)
        if remaining.nanoseconds > 0 { try await Task.sleep(nanoseconds: UInt64(remaining.nanoseconds)) }
    }

    public func measure(_ work: () async throws -> Void) async rethrows -> HostDuration {
        let start = Instant.now
        try await work()
        return start.duration(to: Instant.now)
    }
}

extension Task where Success == Never, Failure == Never {
    /// `Task.sleep(for:)` (macOS 13) for macOS 12.
    public static func hostSleep(for duration: HostDuration) async throws {
        if duration.nanoseconds > 0 { try await Task.sleep(nanoseconds: UInt64(duration.nanoseconds)) }
    }
}
