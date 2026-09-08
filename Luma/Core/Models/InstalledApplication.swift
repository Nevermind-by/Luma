import Foundation

struct InstalledApplication: Identifiable, Hashable, Sendable {
    let id: ApplicationIdentity
    let name: String
    let version: SoftwareVersion
    let bundleURL: URL
}
