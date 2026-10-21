import Foundation

/// A span of time (nanosecond resolution, ±292 years): the part of `Swift.Duration` the app uses.
public struct HostDuration: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var nanoseconds: Int64

    public init(nanoseconds: Int64) { self.nanoseconds = nanoseconds }

    public static let zero = HostDuration(nanoseconds: 0)

    public static func seconds<T: BinaryInteger>(_ value: T) -> HostDuration {
        HostDuration(nanoseconds: Int64(clamping: value).multipliedReportingOverflow(by: 1_000_000_000).partialValue)
    }
    public static func seconds(_ value: Double) -> HostDuration { HostDuration(nanoseconds: scaled(value, 1e9)) }
    public static func milliseconds<T: BinaryInteger>(_ value: T) -> HostDuration {
        HostDuration(nanoseconds: Int64(clamping: value).multipliedReportingOverflow(by: 1_000_000).partialValue)
    }
    public static func milliseconds(_ value: Double) -> HostDuration { HostDuration(nanoseconds: scaled(value, 1e6)) }
    public static func microseconds<T: BinaryInteger>(_ value: T) -> HostDuration {
        HostDuration(nanoseconds: Int64(clamping: value).multipliedReportingOverflow(by: 1_000).partialValue)
    }
    public static func microseconds(_ value: Double) -> HostDuration { HostDuration(nanoseconds: scaled(value, 1e3)) }
    public static func nanoseconds<T: BinaryInteger>(_ value: T) -> HostDuration {
        HostDuration(nanoseconds: Int64(clamping: value))
    }

    private static func scaled(_ value: Double, _ factor: Double) -> Int64 {
        let product = value * factor
        if product.isNaN { return 0 }
        if product >= Double(Int64.max) { return Int64.max }
        if product <= Double(Int64.min) { return Int64.min }
        return Int64(product.rounded())
    }

    /// Whole seconds and the remainder in attoseconds, as `Duration.components`.
    public var components: (seconds: Int64, attoseconds: Int64) {
        let (seconds, rest) = nanoseconds.quotientAndRemainder(dividingBy: 1_000_000_000)
        return (seconds, rest * 1_000_000_000)
    }

    public var timeInterval: TimeInterval { Double(nanoseconds) / 1e9 }

    public static func < (lhs: HostDuration, rhs: HostDuration) -> Bool { lhs.nanoseconds < rhs.nanoseconds }

    public static func + (lhs: HostDuration, rhs: HostDuration) -> HostDuration {
        HostDuration(nanoseconds: lhs.nanoseconds &+ rhs.nanoseconds)
    }
    public static func - (lhs: HostDuration, rhs: HostDuration) -> HostDuration {
        HostDuration(nanoseconds: lhs.nanoseconds &- rhs.nanoseconds)
    }
    public static func += (lhs: inout HostDuration, rhs: HostDuration) { lhs = lhs + rhs }
    public static func -= (lhs: inout HostDuration, rhs: HostDuration) { lhs = lhs - rhs }
    public static prefix func - (value: HostDuration) -> HostDuration { HostDuration(nanoseconds: 0 &- value.nanoseconds) }

    public static func * <T: BinaryInteger>(lhs: HostDuration, rhs: T) -> HostDuration {
        HostDuration(nanoseconds: lhs.nanoseconds &* Int64(clamping: rhs))
    }
    public static func * (lhs: HostDuration, rhs: Double) -> HostDuration {
        HostDuration(nanoseconds: scaled(Double(lhs.nanoseconds) * rhs, 1))
    }
    public static func / <T: BinaryInteger>(lhs: HostDuration, rhs: T) -> HostDuration {
        HostDuration(nanoseconds: lhs.nanoseconds / Int64(clamping: rhs))
    }
    public static func / (lhs: HostDuration, rhs: Double) -> HostDuration {
        HostDuration(nanoseconds: scaled(Double(lhs.nanoseconds) / rhs, 1))
    }
    public static func / (lhs: HostDuration, rhs: HostDuration) -> Double {
        Double(lhs.nanoseconds) / Double(rhs.nanoseconds)
    }

    public var description: String {
        let seconds = timeInterval
        return abs(seconds) >= 1 ? String(format: "%.3f seconds", seconds) : String(format: "%.3f milliseconds", seconds * 1000)
    }
}
