import Foundation

/// Advance from the start of the last successful scan, with overlap for log
/// persistence and one-second CLI timestamp precision. Failed scans retry with
/// backoff so a persistent error cannot start a full-history scan every tick.
struct SystemGameModeHistoryCursor {
    private static let overlap: TimeInterval = 10
    private static let retryDelay: TimeInterval = 60
    private(set) var nextStart: Date?
    private(set) var retryAfterUptime: TimeInterval?

    func scanStart(now: Date, uptime: TimeInterval) -> Date? {
        if let retryAfterUptime, uptime < retryAfterUptime { return nil }
        let initialStart = now.addingTimeInterval(-max(0, uptime))
        guard let nextStart else { return initialStart }
        // A backward wall-clock adjustment must not create an empty window.
        return min(nextStart, now.addingTimeInterval(-Self.overlap))
    }

    mutating func finish(startedAt: Date, finishedUptime: TimeInterval, succeeded: Bool) {
        if succeeded {
            nextStart = startedAt.addingTimeInterval(-Self.overlap)
            retryAfterUptime = nil
        } else {
            retryAfterUptime = finishedUptime + Self.retryDelay
        }
    }
}

/// Reads observed Game Mode transitions from the system log. Apple does not
/// publish a subscription API for this state, so missing evidence stays unknown.
final class SystemGameModeMonitor {
    struct Entry: Decodable {
        let eventMessage: String
        let machTimestamp: UInt64

        var active: Bool? {
            let message = eventMessage.lowercased()
            // macOS can keep Game Mode enabled for a session while temporarily
            // pausing its optimizations. Keep the pet in game mode until off.
            if message == "game mode status is now on." || message == "game mode status is now paused." ||
                message.hasPrefix("game mode is on,") || message.hasPrefix("game mode is paused,") { return true }
            if message == "game mode status is now off." || message.hasPrefix("game mode is off,") { return false }
            return nil
        }

        var isUnknownTransition: Bool {
            eventMessage.lowercased() == "game mode status is now unavailable."
        }
    }

    private let predicate = """
        (process == "gamepolicyd" OR process == "GamePolicyAgent") AND
        (eventMessage BEGINSWITH[c] "Game mode status is now " OR
         eventMessage BEGINSWITH[c] "Game mode is on," OR
         eventMessage BEGINSWITH[c] "Game mode is paused," OR eventMessage BEGINSWITH[c] "Game mode is off,")
        """
    private var stream: Process?
    private var history: Process?
    private var refreshTimer: Timer?
    private var historyCursor = SystemGameModeHistoryCursor()
    private var lastTimestamp: UInt64?
    private(set) var active: Bool?
    var onChange: (() -> Void)?
    private let logExecutable: URL

    init(logExecutable: URL = URL(fileURLWithPath: "/usr/bin/log")) {
        self.logExecutable = logExecutable
    }

    func start() {
        guard stream == nil else { return }
        do {
            stream = try launch(["stream"]) { [weak self] process, entry in
                guard self?.stream === process else { return }
                self?.accept(entry)
            } finished: { [weak self] process, _ in
                guard self?.stream === process else { return }
                self?.stop()
                self?.onChange?()
            }
        } catch { return }

        refreshFromHistory()
        // Unified log streaming can delay delivery when output is redirected.
        // Reconcile the latest persisted transition as well, including after wake.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshFromHistory()
        }
    }

    private func refreshFromHistory() {
        guard stream != nil, history == nil else { return }
        let startedAt = Date()
        guard let start = historyCursor.scanStart(now: startedAt, uptime: ProcessInfo.processInfo.systemUptime) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        do {
            history = try launch(["show", "--start", formatter.string(from: start)], latestOnly: true) { [weak self] process, entry in
                guard self?.history === process else { return }
                self?.accept(entry)
            } finished: { [weak self] process, succeeded in
                guard let self, self.history === process else { return }
                self.historyCursor.finish(startedAt: startedAt, finishedUptime: ProcessInfo.processInfo.systemUptime, succeeded: succeeded)
                self.history = nil
            }
        } catch {
            historyCursor.finish(startedAt: startedAt, finishedUptime: ProcessInfo.processInfo.systemUptime, succeeded: false)
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        for process in [stream, history].compactMap({ $0 }) where process.isRunning { process.terminate() }
        stream = nil
        history = nil
        historyCursor = SystemGameModeHistoryCursor()
        lastTimestamp = nil
        active = nil
    }

    private func accept(_ entry: Entry) {
        guard entry.active != nil || entry.isUnknownTransition,
              lastTimestamp.map({ entry.machTimestamp > $0 }) ?? true else { return }
        lastTimestamp = entry.machTimestamp
        guard active != entry.active else { return }
        active = entry.active
        onChange?()
    }

    private func launch(_ arguments: [String], latestOnly: Bool = false,
                        receive: @escaping (Process, Entry) -> Void,
                        finished: @escaping (Process, Bool) -> Void) throws -> Process {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = logExecutable
        process.arguments = arguments + ["--info", "--style", "ndjson", "--predicate", predicate]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        DispatchQueue.global(qos: .utility).async {
            let reader = pipe.fileHandleForReading
            let decoder = JSONDecoder()
            var pending = Data()
            var latest: Entry?
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    guard let entry = try? decoder.decode(Entry.self, from: line),
                          entry.active != nil || entry.isUnknownTransition else { continue }
                    if latestOnly {
                        if latest.map({ $0.machTimestamp < entry.machTimestamp }) ?? true { latest = entry }
                    } else {
                        DispatchQueue.main.async { receive(process, entry) }
                    }
                }
            }
            if let latest { DispatchQueue.main.async { receive(process, latest) } }
            process.waitUntilExit()
            let succeeded = process.terminationReason == .exit && process.terminationStatus == 0
            DispatchQueue.main.async { finished(process, succeeded) }
        }
        return process
    }

    deinit { stop() }
}
