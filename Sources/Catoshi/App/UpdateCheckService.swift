import Foundation

struct CatoshiVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ value: String) {
        let tag = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = tag.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              numbers.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && ($0.count == 1 || $0.first != "0") }),
              let major = Int(numbers[0]), let minor = Int(numbers[1]), let patch = Int(numbers[2]) else { return nil }
        let prerelease = pieces.count == 2 ? pieces[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard pieces.count == 1 || (!prerelease.isEmpty && prerelease.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
                && (!part.utf8.allSatisfy { (48...57).contains($0) } || part.count == 1 || part.first != "0")
        })) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch; self.prerelease = prerelease
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = left.utf8.allSatisfy { (48...57).contains($0) }
            let rightNumeric = right.utf8.allSatisfy { (48...57).contains($0) }
            if leftNumeric != rightNumeric { return leftNumeric }
            if leftNumeric && left.count != right.count { return left.count < right.count }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct CatoshiRelease: Decodable, Equatable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease
    }

    var version: CatoshiVersion? { CatoshiVersion(tagName) }
    var url: URL {
        // Never open an API-supplied URL or another repository.
        CatoshiCommunity.githubRepositoryURL.appendingPathComponent("releases/tag").appendingPathComponent(tagName)
    }
}

enum UpdateCheckError: Error {
    case invalidResponse, rateLimited, noRelease, invalidCurrentVersion, incompleteList
}

struct UpdateCheckResult {
    let current: CatoshiVersion
    let latest: CatoshiRelease
    var hasUpdate: Bool { latest.version.map { current < $0 } ?? false }
    var isAhead: Bool { latest.version.map { $0 < current } ?? false }
}

struct UpdateCheckService {
    private let session: URLSession

    private static let publicSession: URLSession = {
        let configuration = CatoshiNetworkRuntime.ephemeralConfiguration(requestTimeout: 10, resourceTimeout: 15, waitsForConnectivity: false)
        configuration.httpAdditionalHeaders = ["User-Agent": "Catoshi-UpdateCheck", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
        return URLSession(configuration: configuration)
    }()

    init(session: URLSession? = nil) {
        self.session = session ?? Self.publicSession
    }

    static func newest(in releases: [CatoshiRelease]) -> CatoshiRelease? {
        releases.filter { !$0.draft && $0.version != nil }.max { $0.version! < $1.version! }
    }

    func check(currentVersion: String) async throws -> UpdateCheckResult {
        guard let current = CatoshiVersion(currentVersion) else { throw UpdateCheckError.invalidCurrentVersion }
        var releases: [CatoshiRelease] = []
        // The list endpoint includes public beta releases, unlike /releases/latest.
        for page in 1...5 {
            try Task.checkCancellation()
            let url = URL(string: "https://api.github.com/repos/Rayeonjin/Catoshi/releases?per_page=100&page=\(page)")!
            let (data, response) = try await session.data(for: URLRequest(url: url))
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
            if http.statusCode == 403 || http.statusCode == 429 { throw UpdateCheckError.rateLimited }
            guard http.statusCode == 200 else { throw UpdateCheckError.invalidResponse }
            let batch = try JSONDecoder().decode([CatoshiRelease].self, from: data)
            releases.append(contentsOf: batch)
            if batch.count < 100 {
                guard let latest = Self.newest(in: releases) else { throw UpdateCheckError.noRelease }
                return UpdateCheckResult(current: current, latest: latest)
            }
        }
        throw UpdateCheckError.incompleteList
    }
}
