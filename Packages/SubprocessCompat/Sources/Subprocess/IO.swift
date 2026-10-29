// Input and output choices: `.none`, `.inputWriter`; `.discarded`, `.string(limit:)`, `.sequence`, `.fileDescriptor`.

import Foundation
import System

public enum _InputSpec: Sendable {
    case none
    case writer
}

public enum _OutputSpec: Sendable {
    case discarded
    case string(limit: Int)
    case sequence
    case fileDescriptor(FileDescriptor, closeAfterSpawningProcess: Bool)
}

public protocol InputProtocol: Sendable {
    var _spec: _InputSpec { get }
}

public struct NoInput: InputProtocol {
    public var _spec: _InputSpec { .none }
    public init() {}
}

/// The body writes to the child's standard input through `Execution.standardInputWriter`.
public struct WriterInput: InputProtocol {
    public var _spec: _InputSpec { .writer }
    public init() {}
}

extension InputProtocol where Self == NoInput {
    public static var none: NoInput { NoInput() }
}

extension InputProtocol where Self == WriterInput {
    public static var inputWriter: WriterInput { WriterInput() }
}

public protocol OutputProtocol: Sendable {
    associatedtype OutputType: Sendable
    var _spec: _OutputSpec { get }
    func _finalize(_ bytes: [UInt8]?) -> OutputType
}

public struct DiscardedOutput: OutputProtocol {
    public typealias OutputType = Void
    public var _spec: _OutputSpec { .discarded }
    public func _finalize(_ bytes: [UInt8]?) -> Void {}
}

/// Collected as a String; bytes past `limit` are dropped.
public struct StringOutput: OutputProtocol {
    public typealias OutputType = String
    let limit: Int
    public var _spec: _OutputSpec { .string(limit: limit) }
    public func _finalize(_ bytes: [UInt8]?) -> String { String(decoding: bytes ?? [], as: UTF8.self) }
}

/// Read by the body through `Execution.standardOutput` / `standardError`.
public struct SequenceOutput: OutputProtocol {
    public typealias OutputType = Void
    public var _spec: _OutputSpec { .sequence }
    public func _finalize(_ bytes: [UInt8]?) -> Void {}
}

public struct FileDescriptorOutput: OutputProtocol {
    public typealias OutputType = Void
    let fileDescriptor: FileDescriptor
    let close: Bool
    public var _spec: _OutputSpec { .fileDescriptor(fileDescriptor, closeAfterSpawningProcess: close) }
    public func _finalize(_ bytes: [UInt8]?) -> Void {}
}

extension OutputProtocol where Self == DiscardedOutput {
    public static var discarded: DiscardedOutput { DiscardedOutput() }
}

extension OutputProtocol where Self == StringOutput {
    public static func string(limit: Int) -> StringOutput { StringOutput(limit: limit) }
}

extension OutputProtocol where Self == SequenceOutput {
    public static var sequence: SequenceOutput { SequenceOutput() }
}

extension OutputProtocol where Self == FileDescriptorOutput {
    public static func fileDescriptor(_ fileDescriptor: FileDescriptor, closeAfterSpawningProcess: Bool)
        -> FileDescriptorOutput
    {
        FileDescriptorOutput(fileDescriptor: fileDescriptor, close: closeAfterSpawningProcess)
    }
}

// MARK: Execution handed to a `run` body

public struct BufferingPolicy: Sendable {
    let maxLine: Int?
    public static var unbounded: BufferingPolicy { BufferingPolicy(maxLine: nil) }
    public static func maxLineLength(_ length: Int) -> BufferingPolicy { BufferingPolicy(maxLine: length) }
}

/// The child's output as it arrives. One consumer.
public struct AsyncBufferSequence: Sendable {
    let chunks: AsyncStream<[UInt8]>

    /// UTF-8 lines (split at "\n", a trailing "\r" dropped); a line longer than the policy's limit comes out in pieces.
    public func strings(bufferingPolicy: BufferingPolicy = .maxLineLength(128 * 1024)) -> AsyncThrowingStream<String, Error> {
        let chunks = self.chunks
        let limit = bufferingPolicy.maxLine
        return AsyncThrowingStream { continuation in
            let reader = Task {
                var buffer: [UInt8] = []
                func emit(_ bytes: ArraySlice<UInt8>) {
                    var line = bytes
                    if line.last == 13 { line = line.dropLast() }
                    continuation.yield(String(decoding: line, as: UTF8.self))
                }
                for await chunk in chunks {
                    buffer.append(contentsOf: chunk)
                    var start = 0
                    while let newline = buffer[start...].firstIndex(of: 10) {
                        emit(buffer[start..<newline])
                        start = newline + 1
                    }
                    if start > 0 { buffer.removeFirst(start) }
                    if let limit, limit > 0 {
                        while buffer.count > limit {
                            emit(buffer[0..<limit])
                            buffer.removeFirst(limit)
                        }
                    }
                }
                if !buffer.isEmpty { emit(buffer[...]) }
                continuation.finish()
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}

public final class StandardInputWriter: @unchecked Sendable {
    private let handle: FileHandle?
    private let queue = DispatchQueue(label: "Subprocess.stdin")
    private let lock = NSLock()
    private var closed = false

    init(handle: FileHandle?) {
        self.handle = handle
        if let handle {
            // A child that exits early must give an error on write, not SIGPIPE.
            _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        }
    }

    /// Writes all of `sequence`; returns the byte count.
    @discardableResult
    public func write<S: Sequence>(_ sequence: S) async throws -> Int where S.Element == UInt8 {
        let data = Data(sequence)
        guard let handle else { throw SubprocessError("This process doesn’t take standard input.") }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try handle.write(contentsOf: data)
                    continuation.resume(returning: data.count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @discardableResult
    public func write(_ string: String) async throws -> Int { try await write(Array(string.utf8)) }

    /// Closes the child's standard input (it sees end of file).
    public func finish() async throws { close() }

    func close() {
        // Behind earlier writes, so finish() never cuts one off.
        queue.async { [self] in
            lock.lock()
            defer { lock.unlock() }
            guard !closed else { return }
            closed = true
            try? handle?.close()
        }
    }
}

public final class Execution: @unchecked Sendable {
    public let processIdentifier: ProcessIdentifier
    public let standardInputWriter: StandardInputWriter
    public let standardOutput: AsyncBufferSequence
    public let standardError: AsyncBufferSequence

    init(
        processIdentifier: ProcessIdentifier, standardInputWriter: StandardInputWriter,
        standardOutput: AsyncBufferSequence, standardError: AsyncBufferSequence
    ) {
        self.processIdentifier = processIdentifier
        self.standardInputWriter = standardInputWriter
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
