import Foundation

enum EmergencyCallHandoff {
    static let defaultNumber = "911"
    static let defaultsKey = "emergencyCallNumber"

    static func sanitizedNumber(_ input: String) -> String {
        String(input.filter { "0123456789".contains($0) }.prefix(8))
    }

    static func phoneURL(for number: String) -> URL? {
        let sanitized = sanitizedNumber(number)
        guard !sanitized.isEmpty else { return nil }
        return URL(string: "tel:\(sanitized)")
    }
}
