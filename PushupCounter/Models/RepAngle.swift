import Foundation

struct RepAngle: Codable, Equatable {
    let minAngle: Double
    let maxAngle: Double

    var hasFullRangeOfMotion: Bool {
        minAngle < 90.0 && maxAngle > 160.0
    }
}
