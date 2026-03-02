import Foundation

enum AngleCalculator {
    /// Computes the angle at point `b` formed by the triangle a-b-c, in degrees.
    /// Returns 0 if any vector has zero length.
    static func angle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)

        let dot = ba.dx * bc.dx + ba.dy * bc.dy
        let magBA = sqrt(ba.dx * ba.dx + ba.dy * ba.dy)
        let magBC = sqrt(bc.dx * bc.dx + bc.dy * bc.dy)

        guard magBA > 0, magBC > 0 else { return 0 }

        let cosAngle = max(-1, min(1, dot / (magBA * magBC)))
        return acos(cosAngle) * 180.0 / .pi
    }
}
