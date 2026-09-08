import Foundation

nonisolated struct AppsTorrentApplicationResolver: Sendable {
    enum ResolverError: Error, Equatable {
        case noMatch
        case ambiguousMatch
    }

    private let searchProvider: any AppsTorrentSearchProviding

    init(searchProvider: any AppsTorrentSearchProviding) {
        self.searchProvider = searchProvider
    }

    func resolve(application: InstalledApplication) async throws -> URL {
        let results = try await searchProvider.search(for: application.name)
        let matches = results
            .compactMap { result -> Match? in
                guard let score = score(applicationName: application.name, resultTitle: result.title) else {
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

    private func score(applicationName: String, resultTitle: String) -> Int? {
        let app = normalize(applicationName)
        let title = normalize(resultTitle)

        guard !app.isEmpty, !title.isEmpty else {
            return nil
        }

        if app == title {
            return 100
        }

        guard title.hasPrefix(app) else {
            return nil
        }

        let suffix = String(title.dropFirst(app.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard isVersionLikeSuffix(suffix) else {
            return nil
        }

        return 90
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
