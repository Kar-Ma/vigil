import Foundation

enum RecordingMode: String, CaseIterable, Identifiable {
    case rear
    case front
    case dual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rear: "Rear Camera"
        case .front: "Front Camera"
        case .dual: "Front + Rear"
        }
    }

    var shortTitle: String {
        switch self {
        case .rear: "Rear"
        case .front: "Front"
        case .dual: "Front + Rear"
        }
    }

    var detail: String {
        switch self {
        case .rear:
            "Records what is happening in front of you."
        case .front:
            "Records you and what is behind you."
        case .dual:
            "Records both cameras with the front camera in picture-in-picture."
        }
    }

    var systemImage: String {
        switch self {
        case .rear: "camera.fill"
        case .front: "person.crop.rectangle"
        case .dual: "rectangle.inset.filled.and.person.filled"
        }
    }
}
