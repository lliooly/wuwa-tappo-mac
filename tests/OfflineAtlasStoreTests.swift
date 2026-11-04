import Foundation

@main struct OfflineAtlasStoreTests {
    static func main() throws {
        let suite = "io.lliooly.wuwa.offline-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = try OfflineAtlasStore(catalog: catalog, defaults: defaults)
        let bag = store.bag()
        precondition(bag.count == 899 && Set(bag.map { $0["asset_id"] as! Int }).count == 899)
        let characters = bag.filter { $0["asset_type"] as? String == "character_skin" }
        let accessory = bag.first { $0["asset_type"] as? String == "accessory" && $0["role_id"] as? String == "0" }!
        let emotes = bag.filter { $0["asset_type"] as? String == "emote" && $0["role_id"] as? String == "0" }
        let appearance: [String: Any] = ["character_asset_id": characters.last!["asset_id"]!,
                                       "accessory_asset_id": accessory["asset_id"]!,
                                       "emote_asset_ids": emotes.prefix(5).map { $0["asset_id"]! }]
        _ = try store.request("appearance", values: appearance)
        _ = try store.request("favorite", values: ["asset_id": characters.last!["asset_id"]!, "enabled": true])
        for _ in 0..<10 { _ = try store.request("create-preset", values: appearance) }
        func rejects(_ action: String, _ values: [String: Any]) {
            do { _ = try store.request(action, values: values); preconditionFailure("Accepted invalid action: \(action)") }
            catch { }
        }
        rejects("create-preset", appearance)
        rejects("appearance", ["character_asset_id": accessory["asset_id"]!])
        rejects("appearance", ["character_asset_id": true])
        rejects("appearance", ["emote_asset_ids": emotes.prefix(6).map { $0["asset_id"]! }])
        rejects("appearance", ["emote_asset_ids": [emotes[0]["asset_id"]!, emotes[0]["asset_id"]!]])
        rejects("favorite", ["asset_id": -1, "enabled": true])
        rejects("delete-preset", ["preset_id": 99999])
        rejects("online", [:])
        let restored = try OfflineAtlasStore(catalog: catalog, defaults: defaults)
        precondition((restored.user()["character"] as! [String: Any])["id"] as! Int == characters.last!["asset_id"] as! Int)
        precondition(restored.presets().count == 10)
        precondition(restored.bag().first { $0["asset_id"] as? Int == characters.last!["asset_id"] as? Int }!["is_collect"] as! Int == 1)
        _ = try restored.request("delete-preset", values: ["preset_id": restored.presets()[0]["preset_id"]!])
        precondition(restored.presets().count == 9)
        // A role change must drop exclusive items, while universal items survive.
        if let exclusive = bag.first(where: { $0["asset_type"] as? String == "emote" && $0["role_id"] as? String != "0" }),
           let owner = characters.first(where: { $0["role_id"] as? String == exclusive["role_id"] as? String }),
           let other = characters.first(where: { $0["role_id"] as? String != exclusive["role_id"] as? String }) {
            _ = try restored.request("appearance", values: ["character_asset_id": owner["asset_id"]!, "emote_asset_ids": [exclusive["asset_id"]!]])
            precondition((restored.user()["emote"] as! [[String: Any]]).count == 1)
            _ = try restored.request("appearance", values: ["character_asset_id": other["asset_id"]!])
            precondition((restored.user()["emote"] as! [[String: Any]]).isEmpty)
        }
        defaults.set(["version": 1, "character_asset_id": -1], forKey: "offlineFullAtlasV1")
        let recovered = try OfflineAtlasStore(catalog: catalog, defaults: defaults)
        precondition(!recovered.recoveryMessage.isEmpty && recovered.presets().isEmpty)
        print("PASS: 899 mapped items, appearance validation, role restrictions, limits, favorites, presets, persistence and corrupt-state recovery")
    }
}
