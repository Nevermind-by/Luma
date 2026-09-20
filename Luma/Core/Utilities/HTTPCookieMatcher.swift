import Foundation

enum HTTPCookieMatcher {
    static func matchingCookies(_ cookies: [HTTPCookie], for url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }

        let requestPath = normalizedPath(url.path)
        let now = Date()

        return cookies.filter { cookie in
            guard !cookie.isExpired(at: now) else { return false }

            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))

            let hostMatches = host == domain || host.hasSuffix(".\(domain)")
            guard hostMatches else { return false }

            if cookie.isSecure && url.scheme?.lowercased() != "https" {
                return false
            }

            let cookiePath = normalizedCookiePath(cookie.path)
            return requestPath == cookiePath
                || cookiePath == "/"
                || requestPath.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/")
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    private static func normalizedCookiePath(_ path: String) -> String {
        guard !path.isEmpty else { return "/" }
        return path.hasPrefix("/") ? path : "/"
    }
}

private extension HTTPCookie {
    func isExpired(at date: Date) -> Bool {
        guard let expiresDate else { return false }
        return expiresDate <= date
    }
}
