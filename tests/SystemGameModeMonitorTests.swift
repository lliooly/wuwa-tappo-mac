import Foundation

@main struct SystemGameModeMonitorTests {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        let now = Date(timeIntervalSince1970: 100_000)
        var cursor = SystemGameModeHistoryCursor()
        check(cursor.scanStart(now: now, uptime: 3_600) == now.addingTimeInterval(-3_600),
              "The first scan must include the current boot")
        cursor.finish(startedAt: now, finishedUptime: 3_630, succeeded: true)
        check(cursor.scanStart(now: now.addingTimeInterval(33), uptime: 3_633) == now.addingTimeInterval(-10),
              "Catch up from before the preceding scan began, not when it ended")
        let secondStart = now.addingTimeInterval(33)
        cursor.finish(startedAt: secondStart, finishedUptime: 3_634, succeeded: true)
        check(cursor.scanStart(now: now.addingTimeInterval(36), uptime: 3_636) == now.addingTimeInterval(23),
              "Later scans must be incremental and overlapping")
        let failure = now.addingTimeInterval(36)
        cursor.finish(startedAt: failure, finishedUptime: 3_638, succeeded: false)
        check(cursor.scanStart(now: now.addingTimeInterval(97), uptime: 3_697) == nil,
              "Failed scans must be backed off")
        check(cursor.scanStart(now: now.addingTimeInterval(98), uptime: 3_698) == now.addingTimeInterval(23),
              "A failed scan must not discard its unscanned interval")
        check(cursor.scanStart(now: now.addingTimeInterval(-30), uptime: 3_670) == nil,
              "A backward clock change must not bypass failure backoff")

        var clockChange = SystemGameModeHistoryCursor()
        clockChange.finish(startedAt: now, finishedUptime: 3_600, succeeded: true)
        check(clockChange.scanStart(now: now.addingTimeInterval(-20), uptime: 3_580) == now.addingTimeInterval(-30),
              "Backward clock changes must still scan a nonempty recent window")
        let decoder = JSONDecoder()
        for (message, expected) in [("Game mode status is now on.", true),
                                    ("Game mode status is now paused.", true),
                                    ("Game mode status is now off.", false)] {
            let data = try JSONSerialization.data(withJSONObject: ["eventMessage": message, "machTimestamp": 42])
            let entry = try decoder.decode(SystemGameModeMonitor.Entry.self, from: data)
            check(entry.active == expected, "Game Mode transition parsing changed")
        }
        let unknown = try JSONSerialization.data(withJSONObject: ["eventMessage": "Game mode status is now unavailable.",
                                                                   "machTimestamp": 43])
        let unknownEntry = try decoder.decode(SystemGameModeMonitor.Entry.self, from: unknown)
        check(unknownEntry.isUnknownTransition, "Unavailable Game Mode state must stay unknown")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wuwa-log-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("log")
        let calls = dir.appendingPathComponent("calls")
        let scriptBody = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(calls.path)'
        if [ "$1" = stream ]; then exec /bin/sleep 30; fi
        printf '%s\\n' '{"eventMessage":"Game mode status is now on.","machTimestamp":100}'
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let monitor = SystemGameModeMonitor(logExecutable: script)
        var changes = 0
        monitor.onChange = { changes += 1 }
        monitor.start()
        RunLoop.current.run(until: Date().addingTimeInterval(7.5))
        check(monitor.active == true && changes == 1, "Log process must publish and deduplicate state")
        monitor.stop()
        let lines = try String(contentsOf: calls, encoding: .utf8).components(separatedBy: .newlines)
        let shows = lines.filter { $0.hasPrefix("show --start ") }
        check(lines.filter { $0.hasPrefix("stream ") }.count == 1, "Expected exactly one log stream")
        check(shows.count >= 2, "Expected an initial history scan and an incremental scan")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func startTime(_ line: String) -> Date? {
            let prefix = "show --start "
            return formatter.date(from: String(line.dropFirst(prefix.count).prefix(19)))
        }
        let initial = startTime(shows[0])!
        let incremental = startTime(shows[1])!
        if ProcessInfo.processInfo.systemUptime > 90 {
            check(incremental.timeIntervalSince(initial) > 60,
                  "The second real process must not repeat the full boot history")
        }
        check(abs(incremental.timeIntervalSinceNow) < 30,
              "The second real process must scan a recent, overlapping window")
        print("PASS: boot scan, incremental overlap, backoff, clock change, state parsing and subprocess integration")
    }
}
