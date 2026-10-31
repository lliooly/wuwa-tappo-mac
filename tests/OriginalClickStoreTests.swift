import Foundation

@main struct ClickStoreTests {
    static func main() throws {
        func check(_ condition: Bool, _ message: String = "Storage contract failed") { precondition(condition, message) }
        let suite = "io.lliooly.wuwa-tappo.click-store-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(752, forKey: "localClickCount")
        let env = OriginalClickStore.domesticEnvironment
        var store = OriginalClickStore(defaults: defaults)
        func call(_ command: String, _ values: [String: Any] = [:], environment: String? = nil) throws -> Any {
            try store.invoke(command, args: values.merging(["environment": environment ?? env]) { _, new in new })
        }
        func pending(_ environment: String? = nil) throws -> Int {
            try call("load_key_press_count", environment: environment) as! Int
        }
        func cumulative() throws -> [String: Any] {
            try call("load_cumulative_click_count") as! [String: Any]
        }
        check(try pending("global-prod") == 0)
        check(try pending() == 752)
        check(try cumulative()["cuid"] as? String == "")
        _ = try call("save_cumulative_click_count", ["count": 5_000, "cuid": "account-a"])
        check(try pending() == 752)
        _ = try call("save_key_press_count", ["count": 0])
        check(try cumulative()["count"] as? Int == 5_000)
        store = OriginalClickStore(defaults: defaults)
        check(try pending() == 0, "Legacy clicks imported twice after acknowledgement")
        _ = try call("save_key_press_count", ["count": 23])
        _ = try call("save_cumulative_click_count", ["count": 80, "cuid": "account-b"])
        check(try pending() == 23)
        check(try cumulative()["cuid"] as? String == "account-b")
        check(try cumulative()["count"] as? Int == 80)
        check(try cumulative()["environment"] as? String == env)
        _ = try call("save_key_press_count", ["count": 9], environment: "global-prod")
        check(try pending() == 23)
        check(try pending("global-prod") == 9)
        for invalid: Any in [-1, 0.5, Double.infinity, true, "12", 9_007_199_254_740_992 as Int] {
            do {
                _ = try call("save_key_press_count", ["count": invalid])
                fatalError("Invalid count accepted")
            } catch {}
        }
        do {
            _ = try call("save_cumulative_click_count", ["count": 12, "cuid": " "])
            fatalError("Empty account accepted")
        } catch {}
        check(try pending() == 23)
        check(try cumulative()["count"] as? Int == 80)
        _ = try call("save_key_press_count", ["count": OriginalClickStore.maximumSafeCount])
        check(try pending() == OriginalClickStore.maximumSafeCount)
        print("PASS: migration, persistence, acknowledgement reset, account replacement, environment isolation and invalid writes")
    }
}
