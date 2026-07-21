import Foundation

enum EmergencyCallHandoff {
    static let number = "112"

    static var phoneURL: URL? {
        URL(string: "tel:\(number)")
    }
}
