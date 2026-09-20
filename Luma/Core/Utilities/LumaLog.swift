import Foundation
import OSLog

nonisolated enum LumaLog {
    static func hostDescription(for url: URL) -> String {
        url.host ?? "unknown"
    }

    static let appsTorrent = Logger(
        subsystem: "com.nevermind.Luma",
        category: "AppsTorrent"
    )

    static let updates = Logger(
        subsystem: "com.nevermind.Luma",
        category: "Updates"
    )
}
