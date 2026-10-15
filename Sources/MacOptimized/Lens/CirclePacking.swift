import CoreGraphics
import Foundation

/// Sibling circle packing (greedy front placement): each circle, largest first, is placed tangent
/// to two already-placed circles at the non-overlapping spot closest to the origin.
enum CirclePacking {
    struct Circle { var x: CGFloat; var y: CGFloat; var r: CGFloat }

    static func pack(radii: [CGFloat]) -> [Circle] {
        var placed: [Circle] = []
        for (i, r) in radii.enumerated() {
            switch i {
            case 0: placed.append(Circle(x: 0, y: 0, r: r))
            case 1:
                placed[0].x = -r
                placed.append(Circle(x: placed[0].r, y: 0, r: r))
            default:
                placed.append(bestSpot(for: r, among: placed))
            }
        }
        return placed
    }

    private static func bestSpot(for r: CGFloat, among placed: [Circle]) -> Circle {
        var best: Circle?
        var bestDist = CGFloat.infinity
        for i in 0..<placed.count {
            for j in (i + 1)..<placed.count {
                for c in tangents(placed[i], placed[j], r) {
                    let d = hypot(c.x, c.y)
                    if d < bestDist, !overlaps(c, placed) { best = c; bestDist = d }
                }
            }
        }
        if let best { return best }
        // Fallback: outside everything on the x axis.
        let far = placed.map { hypot($0.x, $0.y) + $0.r }.max() ?? 0
        return Circle(x: far + r, y: 0, r: r)
    }

    /// Circles of radius r tangent (externally) to both a and b.
    private static func tangents(_ a: Circle, _ b: Circle, _ r: CGFloat) -> [Circle] {
        let ra = a.r + r, rb = b.r + r
        let dx = b.x - a.x, dy = b.y - a.y
        let d = hypot(dx, dy)
        guard d > 0, d <= ra + rb, d >= abs(ra - rb) else { return [] }
        let l = (ra * ra - rb * rb + d * d) / (2 * d)
        let h = sqrt(max(0, ra * ra - l * l))
        let mx = a.x + l * dx / d, my = a.y + l * dy / d
        return [
            Circle(x: mx + h * dy / d, y: my - h * dx / d, r: r),
            Circle(x: mx - h * dy / d, y: my + h * dx / d, r: r),
        ]
    }

    private static func overlaps(_ c: Circle, _ all: [Circle]) -> Bool {
        all.contains { hypot($0.x - c.x, $0.y - c.y) < $0.r + c.r - 0.001 }
    }

    /// Radius of the smallest origin-centred circle containing all circles.
    static func boundingRadius(_ circles: [Circle]) -> CGFloat {
        circles.map { hypot($0.x, $0.y) + $0.r }.max() ?? 1
    }
}
