// `run`: spawn a child with Foundation.Process, feed and drain its pipes, wait for it, and tear it down when the
// calling task is cancelled (or the body throws), as swift-subprocess does.

import Foundation
import System

// MARK: Public API

/// Runs the child to completion and collects what `output` and `error` say to collect.
public func run<I: InputProtocol, O: OutputProtocol, E: OutputProtocol>(
    _ executable: Executable,
    arguments: Arguments = [],
    environment: Environment = .inherit,
    workingDirectory: FilePath? = nil,
    platformOptions: PlatformOptions = PlatformOptions(),
    input: I,
    output: O,
    error: E,
    isolation: isolated (any Actor)? = #isolation
) async throws -> CollectedResult<O.OutputType, E.OutputType> {
    let done = try await _launch(
        executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDirectory,
        platformOptions: platformOptions, input: input._spec, output: output._spec, error: error._spec,
        isolation: isolation
    ) { _ in () }
    return CollectedResult(
        processIdentifier: done.pid,
        terminationStatus: done.status,
        standardOutput: output._finalize(done.output),
        standardError: error._finalize(done.error)
    )
}

/// `run` with no input (`input: .none`).
public func run<O: OutputProtocol, E: OutputProtocol>(
    _ executable: Executable,
    arguments: Arguments = [],
    environment: Environment = .inherit,
    workingDirectory: FilePath? = nil,
    platformOptions: PlatformOptions = PlatformOptions(),
    output: O,
    error: E,
    isolation: isolated (any Actor)? = #isolation
) async throws -> CollectedResult<O.OutputType, E.OutputType> {
    try await run(
        executable, arguments: arguments, environment: environment, workingDirectory: workingDirectory,
        platformOptions: platformOptions, input: NoInput(), output: output, error: error, isolation: isolation)
}

/// Runs the child while `body` talks to it (writes its input, reads its `.sequence` output); returns when both the
/// body and the child are done. If the body throws or the task is cancelled the child is torn down first.
public func run<Result, I: InputProtocol, O: OutputProtocol, E: OutputProtocol>(
    _ executable: Executable,
    arguments: Arguments = [],
    environment: Environment = .inherit,
    workingDirectory: FilePath? = nil,
    platformOptions: PlatformOptions = PlatformOptions(),
    input: I,
    output: O,
    error: E,
    isolation: isolated (any Actor)? = #isolation,
    body: (Execution) async throws -> Result
) async throws -> ExecutionResult<Result> {
    let done = try await _launch(
        executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDirectory,
        platformOptions: platformOptions, input: input._spec, output: output._spec, error: error._spec,
        isolation: isolation, body: body
    )
    return ExecutionResult(terminationStatus: done.status, value: done.value)
}

// MARK: Implementation

/// Resumes any number of waiters once the child has exited.
final class ExitWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var status: TerminationStatus?
    private var waiters: [CheckedContinuation<TerminationStatus, Never>] = []

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return status != nil
    }

    func finish(_ newStatus: TerminationStatus) {
        lock.lock()
        guard status == nil else { lock.unlock(); return }
        status = newStatus
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending { waiter.resume(returning: newStatus) }
    }

    func wait() async -> TerminationStatus {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    /// True if the child exited within `timeout` seconds. Polls: used on the teardown path only.
    func waitUntilFinished(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isFinished {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }
}

/// Each step's signal, then up to its delay for the child to exit; SIGKILL after the last step.
private func teardown(
    _ pid: ProcessIdentifier, steps: [PlatformOptions.TeardownStep], waiter: ExitWaiter
) async {
    if waiter.isFinished { return }
    for step in steps {
        kill(pid.value, step.signal.rawValue)
        if await waiter.waitUntilFinished(timeout: step.delay.interval) { return }
    }
    kill(pid.value, SIGKILL)
}

private func readAll(_ handle: FileHandle, limit: Int) async -> [UInt8] {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            var collected: [UInt8] = []
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                if collected.count < limit { collected.append(contentsOf: chunk.prefix(limit - collected.count)) }
            }
            continuation.resume(returning: collected)
        }
    }
}

private func chunkStream(_ handle: FileHandle) -> AsyncStream<[UInt8]> {
    AsyncStream { continuation in
        DispatchQueue.global().async {
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                continuation.yield([UInt8](chunk))
            }
            continuation.finish()
        }
    }
}

private struct Launched<R> {
    var pid: ProcessIdentifier
    var status: TerminationStatus
    var value: R
    var output: [UInt8]?
    var error: [UInt8]?
}

private func _launch<R>(
    executable: Executable,
    arguments: Arguments,
    environment: Environment,
    workingDirectory: FilePath?,
    platformOptions: PlatformOptions,
    input: _InputSpec,
    output: _OutputSpec,
    error: _OutputSpec,
    isolation: isolated (any Actor)?,
    body: (Execution) async throws -> R
) async throws -> Launched<R> {
    if Task.isCancelled { throw CancellationError() }

    let env = environment.resolved()
    let process = Process()
    process.executableURL = try executable.resolve(environment: env)
    process.arguments = arguments.values
    process.environment = env
    if let workingDirectory { process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory.string) }

    // The child's ends of the pipes (and any descriptor the caller handed over) are closed here once it has spawned,
    // or end of file never reaches the readers.
    var closeHandles: [FileHandle] = []
    var closeDescriptors: [FileDescriptor] = []

    var stdinHandle: FileHandle?
    switch input {
    case .none:
        process.standardInput = FileHandle.nullDevice
    case .writer:
        let pipe = Pipe()
        process.standardInput = pipe
        closeHandles.append(pipe.fileHandleForReading)
        stdinHandle = pipe.fileHandleForWriting
    }

    func plan(_ spec: _OutputSpec) -> (target: Any, reader: FileHandle?) {
        switch spec {
        case .discarded:
            return (FileHandle.nullDevice, nil)
        case .string, .sequence:
            let pipe = Pipe()
            closeHandles.append(pipe.fileHandleForWriting)
            return (pipe, pipe.fileHandleForReading)
        case .fileDescriptor(let descriptor, let closeAfter):
            if closeAfter { closeDescriptors.append(descriptor) }
            return (FileHandle(fileDescriptor: descriptor.rawValue, closeOnDealloc: false), nil)
        }
    }
    let outPlan = plan(output)
    let errPlan = plan(error)
    process.standardOutput = outPlan.target
    process.standardError = errPlan.target

    let waiter = ExitWaiter()
    process.terminationHandler = { finished in
        let status: TerminationStatus =
            finished.terminationReason == .uncaughtSignal
            ? .signaled(finished.terminationStatus) : .exited(finished.terminationStatus)
        waiter.finish(status)
    }

    func closeChildEnds() {
        for handle in closeHandles { try? handle.close() }
        for descriptor in closeDescriptors { try? descriptor.close() }
    }

    do {
        try process.run()
    } catch {
        closeChildEnds()
        try? stdinHandle?.close()
        try? outPlan.reader?.close()
        try? errPlan.reader?.close()
        throw SubprocessError("Couldn’t start \(process.executableURL?.lastPathComponent ?? "the process"): \(error.localizedDescription)")
    }
    closeChildEnds()

    let pid = ProcessIdentifier(value: process.processIdentifier)
    let steps = platformOptions.teardownSequence

    // Readers start at once, so a chatty child never blocks on a full pipe.
    var outTask: Task<[UInt8], Never>?
    var errTask: Task<[UInt8], Never>?
    var outChunks = AsyncStream<[UInt8]> { $0.finish() }
    var errChunks = AsyncStream<[UInt8]> { $0.finish() }
    func startReader(
        _ spec: _OutputSpec, _ reader: FileHandle?, task: inout Task<[UInt8], Never>?,
        chunks: inout AsyncStream<[UInt8]>
    ) {
        guard let reader else { return }
        switch spec {
        case .string(let limit): task = Task.detached { await readAll(reader, limit: limit) }
        case .sequence: chunks = chunkStream(reader)
        default: break
        }
    }
    startReader(output, outPlan.reader, task: &outTask, chunks: &outChunks)
    startReader(error, errPlan.reader, task: &errTask, chunks: &errChunks)

    let writer = StandardInputWriter(handle: stdinHandle)
    let execution = Execution(
        processIdentifier: pid, standardInputWriter: writer,
        standardOutput: AsyncBufferSequence(chunks: outChunks), standardError: AsyncBufferSequence(chunks: errChunks))

    let value: R
    do {
        value = try await withTaskCancellationHandler {
            try await body(execution)
        } onCancel: {
            Task.detached { await teardown(pid, steps: steps, waiter: waiter) }
        }
    } catch {
        writer.close()
        // Detached: a cancelled task's own sleeps would return at once and spin the teardown wait.
        await Task.detached { await teardown(pid, steps: steps, waiter: waiter) }.value
        _ = await waiter.wait()
        throw error
    }

    writer.close()
    let status = await withTaskCancellationHandler {
        await waiter.wait()
    } onCancel: {
        Task.detached { await teardown(pid, steps: steps, waiter: waiter) }
    }
    let outBytes = await outTask?.value
    let errBytes = await errTask?.value
    return Launched(pid: pid, status: status, value: value, output: outBytes, error: errBytes)
}
