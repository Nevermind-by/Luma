import Foundation

nonisolated enum PreparedUpdatePayload: Equatable, Sendable {
    case application(URL)
    case diskImage(URL)
    case package(URL)

    var url: URL {
        switch self {
        case .application(let url), .diskImage(let url), .package(let url):
            return url
        }
    }
}
