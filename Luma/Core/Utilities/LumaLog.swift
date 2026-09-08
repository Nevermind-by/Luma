import OSLog

nonisolated enum LumaLog {
    static let appsTorrent = Logger(
        subsystem: "com.nevermind.Luma",
        category: "AppsTorrent"
    )

    static let updates = Logger(
        subsystem: "com.nevermind.Luma",
        category: "Updates"
    )
}
