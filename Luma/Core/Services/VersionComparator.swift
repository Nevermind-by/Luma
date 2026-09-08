import Foundation

nonisolated struct VersionComparator: Sendable {
    nonisolated enum Result: Sendable, Equatable {
        case orderedAscending
        case orderedSame
        case orderedDescending
    }

    func compare(_ lhs: SoftwareVersion, _ rhs: SoftwareVersion) -> Result {
        let left = tokenize(lhs.rawValue)
        let right = tokenize(rhs.rawValue)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftToken = index < left.count ? left[index] : .number(0)
            let rightToken = index < right.count ? right[index] : .number(0)

            switch (leftToken, rightToken) {
            case let (.number(a), .number(b)):
                if a != b {
                    return a < b ? .orderedAscending : .orderedDescending
                }
            case let (.text(a), .text(b)):
                if a != b {
                    return a.localizedStandardCompare(b) == .orderedAscending
                        ? .orderedAscending
                        : .orderedDescending
                }
            case (.number, .text):
                return .orderedDescending
            case (.text, .number):
                return .orderedAscending
            }
        }

        return .orderedSame
    }

    private enum Token {
        case number(Int)
        case text(String)
    }

    private func tokenize(_ value: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsNumber: Bool?

        func flush() {
            guard !current.isEmpty else { return }
            if currentIsNumber == true, let number = Int(current) {
                tokens.append(.number(number))
            } else {
                tokens.append(.text(current.lowercased()))
            }
            current = ""
            currentIsNumber = nil
        }

        for character in value {
            let isNumber = character.isNumber
            if let previous = currentIsNumber, previous != isNumber {
                flush()
            }
            currentIsNumber = isNumber
            if character.isNumber || character.isLetter {
                current.append(character)
            } else {
                flush()
            }
        }

        flush()
        return tokens
    }
}
