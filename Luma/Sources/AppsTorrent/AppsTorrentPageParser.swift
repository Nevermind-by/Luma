import Foundation

nonisolated struct AppsTorrentPageParser: Sendable {
    enum ParserError: Error, Equatable {
        case missingTitle
        case missingVersion
        case missingCurrentReleaseBlock
        case invalidDownloadURL
    }

    func parse(html: String, pageURL: URL) throws -> AppsTorrentRelease {
        guard let title = firstCapture(
            pattern: #"<h1\s+itemprop=[\"']name[\"'][^>]*>\s*(.*?)\s*</h1>"#,
            in: html,
            options: [.caseInsensitive]
        ) else {
            throw ParserError.missingTitle
        }

        guard let version = firstCapture(
            pattern: #"<[^>]*itemprop=[\"']softwareVersion[\"'][^>]*>\s*([^<]+?)\s*</[^>]+>"#,
            in: html,
            options: [.caseInsensitive]
        ) else {
            throw ParserError.missingVersion
        }

        let versionValue = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = try currentReleaseBlock(html: html, version: versionValue)
        let downloadOptions = try parseDownloadOptions(from: block)

        return AppsTorrentRelease(
            title: title.decodedHTML,
            version: SoftwareVersion(versionValue),
            pageURL: pageURL,
            downloadOptions: downloadOptions
        )
    }

    private func currentReleaseBlock(html: String, version: String) throws -> String {
        let escapedVersion = NSRegularExpression.escapedPattern(for: version)
        let pattern = #"<!--\s*dle_spoiler\b[^>]*"# + escapedVersion + #"[^>]*-->.*?(?=<!--\s*dle_spoiler\b|\z)"#

        guard let block = firstCapture(
            pattern: pattern,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            throw ParserError.missingCurrentReleaseBlock
        }

        return block
    }

    private func parseDownloadOptions(from block: String) throws -> [DownloadOption] {
        let patterns: [(String, DownloadOption.Kind)] = [
            (#"<a\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>\s*Прямая ссылка"#, .direct),
            (#"<a\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>\s*Скачать с Mail\.ru"#, .external),
            (#"<a\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>\s*Скачать с MediaFire"#, .external)
        ]

        var options: [DownloadOption] = []

        for (pattern, kind) in patterns {
            guard let rawURL = firstCapture(
                pattern: pattern,
                in: block,
                options: [.caseInsensitive]
            ), let url = URL(string: rawURL) else {
                continue
            }

            let title: String
            switch kind {
            case .direct:
                title = "Direct link"
            case .external:
                title = rawURL.localizedCaseInsensitiveContains("mail.ru") ? "Mail.ru" : "MediaFire"
            }

            options.append(
                DownloadOption(
                    kind: kind,
                    title: title,
                    url: url
                )
            )
        }

        guard !options.isEmpty else {
            throw ParserError.invalidDownloadURL
        }

        return options
    }

    private func firstCapture(
        pattern: String,
        in value: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return String(value[captureRange])
    }
}

private extension String {
    nonisolated var decodedHTML: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
