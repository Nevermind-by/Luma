import Foundation
import Security

nonisolated protocol CodeSignatureVerifying: Sendable {
    func verifyApplication(at url: URL) -> Bool
}

struct CodeSignatureVerifier: CodeSignatureVerifying, Sendable {
    private static let requirement = "anchor apple generic"

    func verifyApplication(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            url as CFURL,
            kSecCSDefaultFlags,
            &staticCode
        )

        guard createStatus == errSecSuccess,
              let staticCode else {
            return false
        }

        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            Self.requirement as CFString,
            kSecCSDefaultFlags,
            &requirement
        )

        guard requirementStatus == errSecSuccess,
              let requirement else {
            return false
        }

        let validationStatus = SecStaticCodeCheckValidity(
            staticCode,
            [kSecCSCheckAllArchitectures],
            requirement
        )

        return validationStatus == errSecSuccess
    }
}
