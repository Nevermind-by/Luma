import Foundation
import OSLog

nonisolated struct AppsTorrentApplicationResolver: Sendable {
    enum ResolverError: Error, Equatable {
        case noMatch
        case ambiguousMatch
    }

    private let searchProvider: any AppsTorrentSearchProviding

    init(searchProvider: any AppsTorrentSearchProviding) {
        self.searchProvider = searchProvider
    }

    func resolveCandidates(for application: InstalledApplication) async throws -> [AppsTorrentSearchResult] {
        LumaLog.appsTorrent.info("Searching AppsTorrent for \(application.name, privacy: .public)")

        let results = try await searchProvider.search(for: application.name)
        LumaLog.appsTorrent.info("AppsTorrent search returned \(results.count, privacy: .public) results")

        let matches = results
            .compactMap { result -> Match? in
                guard let score = score(application: application, resultTitle: result.title) else {
                    return nil
                }
                return Match(result: result, score: score)
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.result.title.localizedStandardCompare($1.result.title) == .orderedAscending
            }

        guard !matches.isEmpty else {
            LumaLog.appsTorrent.error("No AppsTorrent page matched \(application.name, privacy: .public)")
            throw ResolverError.noMatch
        }

        var seenURLs = Set<URL>()
        let candidates = matches.compactMap { match -> AppsTorrentSearchResult? in
            guard seenURLs.insert(match.result.url).inserted else {
                return nil
            }
            return match.result
        }

        LumaLog.appsTorrent.info("Resolved \(candidates.count, privacy: .public) candidate pages for \(application.name, privacy: .public)")
        return candidates
    }

    func resolve(application: InstalledApplication) async throws -> URL {
        let results = try await searchProvider.search(for: application.name)
        let matches = results
            .compactMap { result -> Match? in
                guard let score = score(application: application, resultTitle: result.title) else {
                    return nil
                }
                return Match(result: result, score: score)
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.result.title.localizedStandardCompare($1.result.title) == .orderedAscending
            }

        guard let best = matches.first else {
            throw ResolverError.noMatch
        }

        let equallyBest = matches.filter { $0.score == best.score }
        guard equallyBest.count == 1 else {
            throw ResolverError.ambiguousMatch
        }

        return best.result.url
    }

    private struct Match: Sendable {
        let result: AppsTorrentSearchResult
        let score: Int
    }

    private func score(application: InstalledApplication, resultTitle: String) -> Int? {
        let app = normalize(application.name)
        let title = normalize(stripDistributionMarker(from: resultTitle))

        guard !app.isEmpty, !title.isEmpty else {
            return nil
        }

        let baseScore: Int
        if app == title {
            baseScore = 100
        } else {
            guard title.hasPrefix(app) else {
                return nil
            }

            let suffix = String(title.dropFirst(app.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard isVersionLikeSuffix(suffix) else {
                return nil
            }

            baseScore = 90
        }

        return baseScore + distributionVariantBonus(
            installationSource: application.installationSource,
            resultTitle: resultTitle
        )
    }

    private func distributionVariantBonus(
        installationSource: ApplicationInstallationSource,
        resultTitle: String
    ) -> Int {
        let isMAS = resultTitle.range(
            of: #"\[\s*MAS\s*\]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        switch installationSource {
        case .appStore:
            return isMAS ? 20 : 0
        case .direct:
            return isMAS ? -10 : 20
        case .unknown:
            return 0
        }
    }

    private func stripDistributionMarker(from value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\[\s*MAS\s*\]"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isVersionLikeSuffix(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.split(separator: " ").allSatisfy { token in
            token.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .lowercased()
            .unicodeScalars
            .map { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
            }
            .map(String.init)
            .joined()
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }
}
