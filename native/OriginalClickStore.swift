import Foundation
import CoreFoundation

/// The recovered client keeps pending clicks separate from account gross totals.
final class OriginalClickStore {
    static let domesticEnvironment = "cn-cn-prod"
    static let maximumSafeCount = 9_007_199_254_740_991
    private let defaults: UserDefaults
    private let storageKey = "originalClickStoreV1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func environment(_ args: [String: Any]) throws -> String {
        guard let value = args["environment"] as? String,
              !value.isEmpty, value.count <= 128,
              value.range(of: "^[a-z0-9_-]+$", options: .regularExpression) != nil else {
            throw CocoaError(.coderInvalidValue)
        }
        return value
    }

    private func count(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue <= Double(Self.maximumSafeCount),
              number.doubleValue.rounded(.down) == number.doubleValue else {
            throw CocoaError(.coderInvalidValue)
        }
        return number.intValue
    }

    private func records() -> [String: [String: Any]] {
        defaults.dictionary(forKey: storageKey) as? [String: [String: Any]] ?? [:]
    }

    private func migrateLegacy() {
        // Claim old offline clicks once, only for their original CN environment.
        guard !defaults.bool(forKey: "originalClickStoreV1Migrated") else { return }
        var all = records()
        var domestic = all[Self.domesticEnvironment] ?? [:]
        if domestic["pending"] == nil {
            domestic["pending"] = (try? count(defaults.object(forKey: "localClickCount"))) ?? 0
        }
        all[Self.domesticEnvironment] = domestic
        defaults.set(all, forKey: storageKey)
        defaults.set(true, forKey: "originalClickStoreV1Migrated")
        // Keep the legacy value for rollback, without importing it again.
    }

    func invoke(_ command: String, args: [String: Any]) throws -> Any {
        let env = try environment(args)
        migrateLegacy()
        var all = records()
        var record = all[env] ?? [:]
        switch command {
        case "load_key_press_count":
            return (try? count(record["pending"])) ?? 0
        case "save_key_press_count":
            record["pending"] = try count(args["count"])
        case "load_cumulative_click_count":
            guard let cumulative = record["cumulative"] as? [String: Any],
                  let cuid = cumulative["cuid"] as? String, !cuid.isEmpty,
                  let total = try? count(cumulative["count"]) else {
                return ["count": 0, "cuid": "", "environment": env]
            }
            return ["count": total, "cuid": cuid, "environment": env]
        case "save_cumulative_click_count":
            guard let raw = args["cuid"] as? String else { throw CocoaError(.coderInvalidValue) }
            let cuid = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cuid.isEmpty, cuid.count <= 256 else { throw CocoaError(.coderInvalidValue) }
            record["cumulative"] = ["count": try count(args["count"]), "cuid": cuid]
        default:
            throw CocoaError(.coderInvalidValue)
        }
        all[env] = record
        defaults.set(all, forKey: storageKey)
        return NSNull()
    }
}
