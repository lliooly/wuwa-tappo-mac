import Foundation
import CoreFoundation

/// All windows mutate this one store on the native main thread. No account data.
final class OfflineAtlasStore {
    private let defaults: UserDefaults
    private let key = "offlineFullAtlasV1"
    let items: [[String: Any]]
    private let byID: [Int: [String: Any]]
    private var state: [String: Any]
    private(set) var recoveryMessage = ""
    static let emoteLimit = 5
    static let presetLimit = 10

    init(catalog: URL, defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        guard let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [[String: Any]],
              !rows.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        var index: [Int: [String: Any]] = [:]
        for row in rows {
            guard let id = row["asset_id"] as? Int, id > 0, index[id] == nil,
                  ["character_skin", "accessory", "emote"].contains(row["asset_type"] as? String ?? "") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            index[id] = row
        }
        guard let first = rows.first(where: { $0["asset_type"] as? String == "character_skin" }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        items = rows; byID = index
        let initial: [String: Any] = ["version": 1, "character_asset_id": first["asset_id"]!,
                                    "accessory_asset_id": 0, "emote_asset_ids": [Int](),
                                    "favorites": [Int](), "presets": [[String: Any]]()]
        state = initial
        if let saved = defaults.dictionary(forKey: key) {
            do {
                guard saved["version"] as? Int == 1 else { throw CocoaError(.coderInvalidValue) }
                let appearance = try validateAppearance(saved)
                state.merge(appearance) { _, new in new }
                state["favorites"] = (saved["favorites"] as? [Int] ?? []).filter { index[$0] != nil }
                let presets = saved["presets"] as? [[String: Any]] ?? []
                var ids = Set<Int>()
                state["presets"] = presets.prefix(Self.presetLimit).compactMap { row -> [String: Any]? in
                    guard let id = row["preset_id"] as? Int, id > 0, ids.insert(id).inserted,
                          let valid = try? validateAppearance(row) else { return nil }
                    return valid.merging(["preset_id": id]) { _, new in new }
                }
            } catch {
                state = initial
                recoveryMessage = "离线装扮存档已失效，已恢复默认角色。"
            }
        } else if defaults.object(forKey: key) != nil {
            recoveryMessage = "离线存档无法读取，已恢复默认角色。"
        }
    }

    private func id(_ value: Any?) throws -> Int {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0,
              n.doubleValue <= 9_007_199_254_740_991, n.doubleValue.rounded(.down) == n.doubleValue else {
            throw CocoaError(.coderInvalidValue)
        }
        return n.intValue
    }

    private func item(_ value: Any?, type: String) throws -> [String: Any] {
        let identifier = try id(value)
        guard let row = byID[identifier], row["asset_type"] as? String == type else {
            throw NSError(domain: "OfflineAtlas", code: 1, userInfo: [NSLocalizedDescriptionKey: "本地素材不存在或类型不符。"])
        }
        return row
    }

    private func validateAppearance(_ values: [String: Any]) throws -> [String: Any] {
        let character = try item(values["character_asset_id"], type: "character_skin")
        let role = character["role_id"] as? String ?? "0"
        func compatible(_ row: [String: Any]) -> Bool {
            let owner = row["role_id"] as? String ?? "0"
            return owner == "0" || owner.isEmpty || owner == role
        }
        var accessory = try id(values["accessory_asset_id"] ?? 0)
        if accessory > 0 {
            let row = try item(accessory, type: "accessory")
            // Changing character clears a previously equipped exclusive accessory.
            if !compatible(row) { accessory = 0 }
        }
        guard let rawEmotes = values["emote_asset_ids"] as? [Any], rawEmotes.count <= Self.emoteLimit else {
            throw NSError(domain: "OfflineAtlas", code: 2, userInfo: [NSLocalizedDescriptionKey: "已达到可选表情数量上限。"])
        }
        var emotes = [Int](), seen = Set<Int>()
        for raw in rawEmotes {
            let row = try item(raw, type: "emote"), identifier = try id(raw)
            guard seen.insert(identifier).inserted else { throw CocoaError(.coderInvalidValue) }
            if compatible(row) { emotes.append(identifier) }
        }
        return ["character_asset_id": character["asset_id"]!, "accessory_asset_id": accessory,
                "emote_asset_ids": emotes]
    }

    private func assetView(_ identifier: Int) -> [String: Any]? {
        guard let row = byID[identifier] else { return nil }
        let meta = row["metadata"] as? [String: Any] ?? [:]
        return ["id": identifier, "name": row["asset_name"]!, "x": meta["offset_x"] ?? 0,
                "y": meta["offset_y"] ?? 0, "my_offset_x": meta["my_offset_x"] ?? 0,
                "my_offset_y": meta["my_offset_y"] ?? 0]
    }

    func user() -> [String: Any] {
        let character = state["character_asset_id"] as! Int
        return ["id": 0, "nickname": "全解锁离线版", "player_type": 2,
                "role_id": byID[character]?["role_id"] ?? "0",
                "character": assetView(character)!,
                "accessory": assetView(state["accessory_asset_id"] as? Int ?? 0) as Any? ?? NSNull(),
                "emote": (state["emote_asset_ids"] as? [Int] ?? []).compactMap(assetView),
                "total_click_count": 0, "total_click_consume": 0]
    }

    func bag() -> [[String: Any]] {
        let favorites = Set(state["favorites"] as? [Int] ?? [])
        return items.map { row in
            var result = row
            result.removeValue(forKey: "metadata")
            result["quantity"] = 1; result["owned"] = true
            result["is_collect"] = favorites.contains(row["asset_id"] as! Int) ? 1 : 0
            return result
        }
    }

    func presets() -> [[String: Any]] {
        (state["presets"] as? [[String: Any]] ?? []).map { row in
            var result = row
            result["character_asset_name"] = byID[row["character_asset_id"] as! Int]?["asset_name"]
            result["accessory_asset_name"] = byID[row["accessory_asset_id"] as? Int ?? 0]?["asset_name"]
            result["emotes"] = (row["emote_asset_ids"] as? [Int] ?? []).map {
                ["asset_id": $0, "asset_name": byID[$0]?["asset_name"] ?? ""]
            }
            return result
        }
    }

    func request(_ action: String, values: [String: Any]) throws -> Any {
        switch action {
        case "user": return user()
        case "bag": return bag()
        case "presets": return presets()
        case "status": return ["recoveryMessage": recoveryMessage, "count": items.count]
        default: break
        }
        var next = state
        switch action {
        case "appearance":
            let input = state.merging(values) { _, new in new }
            next.merge(try validateAppearance(input)) { _, new in new }
        case "favorite":
            let identifier = try id(values["asset_id"])
            guard byID[identifier] != nil, let enabled = values["enabled"] as? Bool else { throw CocoaError(.coderInvalidValue) }
            var favorites = Set(state["favorites"] as? [Int] ?? [])
            if enabled { favorites.insert(identifier) } else { favorites.remove(identifier) }
            next["favorites"] = favorites.sorted()
        case "create-preset":
            var rows = state["presets"] as? [[String: Any]] ?? []
            guard rows.count < Self.presetLimit else { throw CocoaError(.coderInvalidValue) }
            var row = try validateAppearance(values)
            row["preset_id"] = (rows.compactMap { $0["preset_id"] as? Int }.max() ?? 0) + 1
            rows.append(row); next["presets"] = rows
        case "delete-preset":
            let identifier = try id(values["preset_id"])
            let rows = state["presets"] as? [[String: Any]] ?? []
            guard rows.contains(where: { $0["preset_id"] as? Int == identifier }) else { throw CocoaError(.coderInvalidValue) }
            next["presets"] = rows.filter { $0["preset_id"] as? Int != identifier }
        default: throw CocoaError(.coderInvalidValue)
        }
        // One complete dictionary write; publish only after validation succeeds.
        defaults.set(next, forKey: key); state = next
        return action == "appearance" ? user() : true
    }
}
