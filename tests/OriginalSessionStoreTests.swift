import Foundation

@main struct SessionStoreTests {
    static func main() throws {
        let log = redactOriginalLog(#"Authorization: Bearer secret123 token=abc&rm=123 {"accessToken":"hidden", "cuid":"account"} mobile=13800000000"#)
        precondition(!log.contains("secret123") && !log.contains("abc") && !log.contains("hidden") && !log.contains("account") && !log.contains("13800000000"))
        precondition(log.contains("rm=123"))
        let service = "io.lliooly.wuwa-tappo.session-test.\(UUID().uuidString)"
        let store = OriginalSessionStore(service: service)
        defer {
            for name in ["infoToken", "lastLoginTime", "lang"] { try? store.set(name: name, value: "", days: -1) }
        }
        precondition(store.snapshot().isEmpty)
        try store.set(name: "infoToken", value: "isolated-test-token", days: 7)
        try store.set(name: "lastLoginTime", value: "123", days: 7)
        let restored = OriginalSessionStore(service: service)
        precondition(restored.snapshot()["infoToken"]?["value"] as? String == "isolated-test-token")
        precondition(restored.snapshot()["lastLoginTime"]?["value"] as? String == "123")
        try store.set(name: "infoToken", value: "", days: -1)
        precondition(OriginalSessionStore(service: service).snapshot()["infoToken"] == nil)
        do { try store.set(name: "unsupported", value: "value", days: 7); fatalError("Unknown key accepted") } catch {}
        print("PASS: log redaction; isolated Keychain session persistence, restore, clear and key restrictions")
    }
}
