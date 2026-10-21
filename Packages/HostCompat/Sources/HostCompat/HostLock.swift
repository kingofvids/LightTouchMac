import Foundation

extension NSLocking {
    /// `NSLocking.withLock` (macOS 13) for macOS 12.
    @inline(__always)
    public func hostWithLock<R>(_ body: () throws -> R) rethrows -> R {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// `OSAllocatedUnfairLock<State>` (macOS 13) for macOS 12: a lock that owns the state it guards.
public final class HostLock<State>: @unchecked Sendable {
    private let mutex = NSLock()
    private var state: State

    public init(initialState: State) { state = initialState }
    /// For state that isn't Sendable; the caller vouches for how it is shared.
    public init(uncheckedState: State) { state = uncheckedState }

    public func hostWithLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        mutex.lock()
        defer { mutex.unlock() }
        return try body(&state)
    }

    public func hostWithLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R {
        try hostWithLock(body)
    }
}
