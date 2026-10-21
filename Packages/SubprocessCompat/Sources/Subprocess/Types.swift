// Value types of the swift-subprocess API subset Light Touch uses (see Package.swift).

import Foundation
import System

public struct SubprocessError: Error, LocalizedError, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
    public var description: String { message }
}

// MARK: Executable, arguments, environment

public struct Executable: Sendable {
    enum Kind: Sendable {
        case path(FilePath)
        case name(String)
    }
    let kind: Kind
    public static func path(_ path: FilePath) -> Executable { Executable(kind: .path(path)) }
    public static func name(_ name: String) -> Executable { Executable(kind: .name(name)) }

    func resolve(environment: [String: String]) throws -> URL {
        switch kind {
        case .path(let path):
            return URL(fileURLWithPath: path.string)
        case .name(let name):
            let search = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":")
            for dir in search {
                let candidate = String(dir) + "/" + name
                if FileManager.default.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
            }
            throw SubprocessError("Couldn’t find \(name) to run.")
        }
    }
}

public struct Arguments: Sendable, ExpressibleByArrayLiteral {
    public var values: [String]
    public init(_ values: [String]) { self.values = values }
    public init(arrayLiteral elements: String...) { self.values = elements }
}

public struct Environment: Sendable {
    public struct Key: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String
        public init(stringLiteral value: String) { self.rawValue = value }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public var description: String { rawValue }
    }

    enum Base: Sendable {
        case inherit
        case custom([String: String])
    }
    var base: Base
    var updates: [Key: String?]

    public static var inherit: Environment { Environment(base: .inherit, updates: [:]) }
    public static func custom(_ values: [Key: String]) -> Environment {
        Environment(base: .custom(Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })), updates: [:])
    }

    /// A nil value removes the variable.
    public func updating(_ newValue: [Key: String?]) -> Environment {
        var copy = self
        for (key, value) in newValue { copy.updates.updateValue(value, forKey: key) }
        return copy
    }

    func resolved() -> [String: String] {
        var env: [String: String]
        switch base {
        case .inherit: env = ProcessInfo.processInfo.environment
        case .custom(let values): env = values
        }
        for (key, value) in updates {
            if let value { env[key.rawValue] = value } else { env.removeValue(forKey: key.rawValue) }
        }
        return env
    }
}

// MARK: Platform options

public struct Signal: Hashable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let hangup = Signal(rawValue: SIGHUP)
    public static let interrupt = Signal(rawValue: SIGINT)
    public static let quit = Signal(rawValue: SIGQUIT)
    public static let terminate = Signal(rawValue: SIGTERM)
    public static let kill = Signal(rawValue: SIGKILL)
}

/// Stands in for `Duration` (macOS 13) in a teardown step: `.seconds(5)`, `.milliseconds(200)`.
public struct TeardownDelay: Sendable {
    public var interval: TimeInterval
    public static func seconds(_ value: Double) -> TeardownDelay { TeardownDelay(interval: value) }
    public static func milliseconds(_ value: Double) -> TeardownDelay { TeardownDelay(interval: value / 1000) }
}

public struct PlatformOptions: Sendable {
    public struct TeardownStep: Sendable {
        let signal: Signal
        let delay: TeardownDelay
        public static func send(signal: Signal, allowedDurationToNextStep: TeardownDelay) -> TeardownStep {
            TeardownStep(signal: signal, delay: allowedDurationToNextStep)
        }
    }
    /// What cancellation (or a throwing body) does to the child: each step's signal, then the wait before the next.
    /// After the last step the child gets SIGKILL.
    public var teardownSequence: [TeardownStep] = []
    public init() {}
}

// MARK: Results

public enum TerminationStatus: Sendable, Hashable, CustomStringConvertible {
    case exited(Int32)
    case signaled(Int32)

    public var isSuccess: Bool {
        if case .exited(0) = self { return true }
        return false
    }
    public var description: String {
        switch self {
        case .exited(let code): "exited(\(code))"
        case .signaled(let signal): "signaled(\(signal))"
        }
    }
}

public struct ProcessIdentifier: Sendable, Hashable {
    public let value: pid_t
}

public struct CollectedResult<Output: Sendable, ErrorOutput: Sendable>: Sendable {
    public let processIdentifier: ProcessIdentifier
    public let terminationStatus: TerminationStatus
    public let standardOutput: Output
    public let standardError: ErrorOutput
}

public struct ExecutionResult<Result> {
    public let terminationStatus: TerminationStatus
    public let value: Result
}
