#if ENABLE_SIDECAR
import Foundation

/// Manages a single Pi RPC subprocess for review-only LLM interaction.
///
/// Each session runs one `pi --mode rpc` process with isolation flags.
/// Protocol: JSONL over stdin/stdout. Single in-flight request per process.
///
/// State machine:
/// ```
/// starting ──(get_state response)──→ ready
/// ready ──(prompt sent)──→ busy
/// busy ──(agent_end)──→ ready
/// busy ──(abort sent)──→ aborting ──(agent_end)──→ ready
/// busy ──(timeout 60s)──→ error ──(auto-restart)──→ starting
/// any ──(process exit)──→ terminated ──(auto-restart if retries < 3)──→ starting
/// ```
final class PiRPCSession {

    // MARK: - Public State

    enum Status: Equatable {
        case starting
        case ready
        case busy
        case aborting
        case error(String)
        case terminated

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.starting, .starting), (.ready, .ready), (.busy, .busy),
                 (.aborting, .aborting), (.terminated, .terminated):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    let modelFlag: String     // e.g. "github-copilot/gpt-5.4"
    let displayName: String   // e.g. "GPT-5.4"
    private(set) var status: Status = .terminated
    var lastUsage: PiTokenUsage?

    /// Called on main thread when status changes.
    var onStatusChange: ((Status) -> Void)?

    // MARK: - Private State

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    private let piPath: String
    private let systemPrompt: String?
    private let writeQueue = DispatchQueue(label: "com.spectra.pirpc.write")
    private var restartCount = 0
    private var lastRestartTime: Date?
    private static let maxRestartsInWindow = 3
    private static let restartWindowSeconds: TimeInterval = 60
    private static let requestTimeoutSeconds: TimeInterval = 120

    // MARK: - Init

    /// - Parameters:
    ///   - modelFlag: Full model identifier, e.g. "github-copilot/gpt-5.4"
    ///   - displayName: Human-readable name for UI, e.g. "GPT-5.4"
    ///   - piPath: Absolute path to the `pi` binary.
    ///   - systemPrompt: Optional system prompt appended via `--append-system-prompt`.
    init(modelFlag: String, displayName: String, piPath: String, systemPrompt: String? = nil) {
        self.modelFlag = modelFlag
        self.displayName = displayName
        self.piPath = piPath
        self.systemPrompt = systemPrompt
    }

    deinit {
        stopSync()
    }

    // MARK: - Lifecycle

    /// Launch the Pi subprocess. Transitions to `.starting`, then `.ready` on success.
    func start() throws {
        guard status == .terminated || {
            if case .error = status { return true }
            return false
        }() else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: piPath)

        var args = ["--mode", "rpc", "--no-session", "--no-tools",
                    "--no-extensions", "--no-skills", "--thinking", "off",
                    "--model", modelFlag]
        if let sp = systemPrompt {
            args += ["--append-system-prompt", sp]
        }
        proc.arguments = args

        // Isolation strategy:
        // - --no-tools --no-extensions --no-skills: disables all tool execution + extension loading
        // - cwd=/tmp: prevents project-level AGENTS.md/context discovery
        // - HOME is NOT overridden: Pi needs ~/.config/gh/ for GitHub Copilot auth
        //   (global ~/.pi/agent/AGENTS.md may load as extra context, but with no tools it's harmless)
        proc.environment = ProcessInfo.processInfo.environment
        proc.currentDirectoryURL = FileManager.default.temporaryDirectory

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.process = proc

        proc.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleTermination(exitCode: proc.terminationStatus)
            }
        }

        setStatus(.starting)
        try proc.run()

        // Start reading stdout in background
        startReading(stdout: stdout)

        // Send get_state to verify readiness
        sendCommand(PiRPCGetStateCommand())
    }

    /// Send a prompt and return an AsyncStream of events.
    /// Only callable when status == .ready.
    func prompt(_ text: String) -> AsyncStream<PiRPCEvent> {
        guard status == .ready else {
            return AsyncStream { $0.finish() }
        }

        setStatus(.busy)
        startTimeout()

        let (stream, continuation) = AsyncStream<PiRPCEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(100)
        )

        // Store continuation for the read loop to yield events
        self.activeContinuation = continuation
        continuation.onTermination = { [weak self] _ in
            self?.activeContinuation = nil
        }

        sendCommand(PiRPCPromptCommand(message: text))

        return stream
    }

    /// Abort the current in-flight request.
    func abort() {
        guard status == .busy else { return }
        setStatus(.aborting)
        sendCommand(PiRPCAbortCommand())
    }

    /// Graceful shutdown: abort → close stdin → SIGTERM → SIGKILL.
    func stop() {
        Task {
            await stopAsync()
        }
    }

    // MARK: - Private: Reading

    private var activeContinuation: AsyncStream<PiRPCEvent>.Continuation?

    private func startReading(stdout: Pipe) {
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let handle = stdout.fileHandleForReading
                for try await line in handle.bytes.lines {
                    guard !Task.isCancelled else { break }
                    guard let event = PiRPCEventParser.parse(line: line) else { continue }

                    await MainActor.run { [weak self] in
                        self?.handleEvent(event)
                    }
                }
            } catch {
                // Read error or pipe broken — expected on process termination
            }
            // EOF — pipe closed
            await MainActor.run { [weak self] in
                if self?.status == .starting || self?.status == .busy {
                    self?.activeContinuation?.finish()
                    self?.activeContinuation = nil
                }
            }
        }
    }

    @MainActor
    private func handleEvent(_ event: PiRPCEvent) {
        switch event {
        case .response(let command, let success, let error):
            if command == "get_state" && success {
                if status == .starting {
                    setStatus(.ready)
                }
            } else if command == "prompt" && !success {
                activeContinuation?.yield(.error(error ?? "prompt failed"))
                finishPrompt()
            }

        case .agentEnd:
            activeContinuation?.yield(event)
            finishPrompt()

        case .messageEnd(let usage):
            if let usage { lastUsage = usage }
            activeContinuation?.yield(event)

        case .messageUpdate, .agentStart, .turnStart, .turnEnd,
             .messageStart, .toolExecutionStart, .toolExecutionEnd:
            activeContinuation?.yield(event)

        case .error(let msg):
            activeContinuation?.yield(event)
            if status == .busy || status == .aborting {
                finishPrompt()
                setStatus(.error(msg))
            }

        case .unknown:
            break
        }
    }

    private func finishPrompt() {
        timeoutTask?.cancel()
        timeoutTask = nil
        activeContinuation?.finish()
        activeContinuation = nil
        if status == .busy || status == .aborting {
            setStatus(.ready)
        }
    }

    // MARK: - Private: Timeout

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.requestTimeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.status == .busy else { return }
                self.activeContinuation?.yield(.error("Request timed out after \(Int(Self.requestTimeoutSeconds))s"))
                self.abort()
            }
        }
    }

    // MARK: - Private: Process Lifecycle

    private func handleTermination(exitCode: Int32) {
        let wasBusy = status == .busy || status == .aborting
        finishPrompt()
        setStatus(.terminated)

        // Auto-restart if within retry budget
        if shouldAutoRestart() {
            restartCount += 1
            lastRestartTime = Date()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                try? self?.start()
            }
        } else if wasBusy {
            setStatus(.error("Pi process exited with code \(exitCode), restart budget exhausted"))
        }
    }

    private func shouldAutoRestart() -> Bool {
        if let lastTime = lastRestartTime,
           Date().timeIntervalSince(lastTime) > Self.restartWindowSeconds {
            restartCount = 0
        }
        return restartCount < Self.maxRestartsInWindow
    }

    // MARK: - Private: Writing

    private func sendCommand<T: Encodable>(_ command: T) {
        writeQueue.async { [weak self] in
            guard let self, let pipe = self.stdinPipe else { return }
            do {
                var data = try JSONEncoder().encode(command)
                data.append(contentsOf: "\n".utf8)
                pipe.fileHandleForWriting.write(data)
            } catch {
                DispatchQueue.main.async {
                    self.setStatus(.error("Failed to encode command: \(error)"))
                }
            }
        }
    }

    // MARK: - Private: Shutdown

    private func stopAsync() async {
        readTask?.cancel()

        if status == .busy {
            sendCommand(PiRPCAbortCommand())
            try? await Task.sleep(for: .seconds(1))
        }

        // Close stdin → Pi receives EOF
        stdinPipe?.fileHandleForWriting.closeFile()
        try? await Task.sleep(for: .seconds(2))

        if let proc = process, proc.isRunning {
            proc.terminate()
            try? await Task.sleep(for: .seconds(1))
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }

        cleanup()
    }

    private func stopSync() {
        readTask?.cancel()
        stdinPipe?.fileHandleForWriting.closeFile()
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        cleanup()
    }

    private func cleanup() {
        activeContinuation?.finish()
        activeContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        setStatus(.terminated)
    }

    // MARK: - Private: Status

    private func setStatus(_ newStatus: Status) {
        guard status != newStatus else { return }
        status = newStatus
        onStatusChange?(newStatus)
    }
}

// MARK: - Pi Binary Discovery

enum PiBinaryResolver {

    /// Resolve the Pi binary path using the priority order from the plan:
    /// 1. User-configured absolute path
    /// 2. Known install locations (nvm, homebrew, /usr/local/bin)
    /// 3. `which pi` PATH lookup
    static func resolve(configuredPath: String? = nil) -> String? {
        // 1. User-configured
        if let path = configuredPath, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        // 2. Known locations
        if let nvmPath = findInNvm() {
            return nvmPath
        }
        let knownPaths = ["/opt/homebrew/bin/pi", "/usr/local/bin/pi"]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. which pi
        return whichPi()
    }

    private static func findInNvm() -> String? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let nvmDir = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: nvmDir, includingPropertiesForKeys: nil
        ) else { return nil }

        // Sort descending to prefer newer Node versions
        let sorted = entries.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for dir in sorted {
            let piPath = dir.appendingPathComponent("bin/pi").path
            if FileManager.default.isExecutableFile(atPath: piPath) {
                return piPath
            }
        }
        return nil
    }

    private static func whichPi() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["pi"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }
}
#endif
