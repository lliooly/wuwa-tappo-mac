import Foundation
import Security

/// Custom WKURLScheme pages cannot use the release's Secure document cookies.
/// Keep the same named values/expiry semantics in a single Keychain record.
final class OriginalSessionStore {
    private let service: String
    private let account = "original-browser-session-v1"
    private var values: [String: [String: Any]]
    private static let allowed = Set(["infoToken", "lastLoginTime", "lang"])

    init(service: String = (Bundle.main.bundleIdentifier ?? "io.lliooly.wuwa-tappo.mac") + ".session") {
        self.service = service
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            values = decoded
        } else { values = [:] }
    }

    func snapshot() -> [String: [String: Any]] {
        values.filter { Self.allowed.contains($0.key) && ($0.value["expires"] as? Double ?? 0) > Date().timeIntervalSince1970 * 1000 }
    }

    func set(name: String, value: String, days: Double) throws {
        guard Self.allowed.contains(name), value.utf8.count <= 32_768,
              days.isFinite, abs(days) <= 3650 else { throw CocoaError(.coderInvalidValue) }
        var next = snapshot()
        if days <= 0 || value.isEmpty { next.removeValue(forKey: name) }
        else { next[name] = ["value": value, "expires": Date().timeIntervalSince1970 * 1000 + days * 86_400_000] }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        if next.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
        } else {
            let data = try JSONSerialization.data(withJSONObject: next)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw error(status) }
        }
        values = next
    }

    private func error(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Unable to persist login session (\(status))"])
    }
}
