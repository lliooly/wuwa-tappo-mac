import Foundation

enum ReleaseUpdate {
    struct Available {
        let version: String
        let page: URL
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int
        }

        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    enum CheckError: Error {
        case unexpectedResponse, invalidRelease, missingPackage
    }

    private static let repository = "lliooly/wuwa-tappo-mac"

    static func check(currentVersion: String) async throws -> Available? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Wuwa-Tappo-mac/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CheckError.unexpectedResponse }
        return try evaluate(data, currentVersion: currentVersion)
    }

    static func evaluate(_ data: Data, currentVersion: String) throws -> Available? {
        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard !release.draft, !release.prerelease,
              let latest = versionComponents(version),
              let installed = versionComponents(currentVersion) else { throw CheckError.invalidRelease }
        guard installed.lexicographicallyPrecedes(latest) else { return nil }

        let packageNames = ["Wuwa-Tappo-mac-arm64.zip", "Wuwa-Tappo-mac-\(version)-arm64.zip"]
        guard release.assets.contains(where: {
            packageNames.contains($0.name) && $0.state == "uploaded" && $0.size > 0
        }) else { throw CheckError.missingPackage }
        // Construct the link from our repository and the validated numeric tag.
        return Available(version: version,
                         page: URL(string: "https://github.com/\(repository)/releases/tag/\(release.tag_name)")!)
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({
            !$0.isEmpty && ($0.count == 1 || $0.first != "0") && $0.utf8.allSatisfy { (48...57).contains($0) }
        }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
}
