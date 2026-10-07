import Testing
import simd
@testable import AgentOfficeCore

@Suite struct OfficeViewProjectionTests {
    let size = (width: 900.0, height: 600.0)

    func toView(_ m: simd_float4x4, _ p: SIMD3<Double>) -> (x: Double, y: Double, z: Double) {
        let c = m * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
        let n = SIMD3<Double>(Double(c.x / c.w), Double(c.y / c.w), Double(c.z / c.w))
        return ((n.x + 1) / 2 * size.width, (1 - n.y) / 2 * size.height, n.z)
    }

    @Test(arguments: [(0.3, -1.1, 37.0), (4.0, 2.0, 120.0), (-2.5, -6.0, 260.0)])
    func viewProjectionMatchesProject(cx: Double, cy: Double, zoom: Double) {
        let viewport = OfficeViewport(centerX: cx, centerY: cy, zoom: zoom)
        let m = viewport.viewProjection(viewSize: size)
        for p in [SIMD3(1.0, 0.0, 2.0), SIMD3(3.5, 1.2, -0.5), SIMD3(-2.0, 0.4, 5.0), SIMD3(8.0, 1.6, 9.0)] {
            let v = toView(m, p)
            let expected = viewport.project(x: p.x, y: p.y, z: p.z, viewSize: size)
            #expect(abs(v.x - expected.x) < 1e-2 && abs(v.y - expected.y) < 1e-2, "\(p): \(v) ≠ \(expected)")
            #expect(v.z > 0 && v.z < 1)
        }
    }

    @Test func pointsTowardTheCameraAreNearer() {
        let viewport = OfficeViewport(centerX: 0, centerY: 0, zoom: 50)
        let m = viewport.viewProjection(viewSize: size)
        #expect(toView(m, SIMD3(2, 1, 2)).z < toView(m, SIMD3(0, 0, 0)).z)
    }

    @Test func lightProjectionCoversBounds() {
        let bounds = PlanRect(minX: -1.5, minZ: -1.5, maxX: 9, maxZ: 6)
        let m = OfficeViewport.lightViewProjection(bounds: bounds, height: 2.5, direction: SIMD3(-0.4, -1, -0.55))
        for x in [bounds.minX, bounds.maxX] {
            for z in [bounds.minZ, bounds.maxZ] {
                for y in [0.0, 2.5] {
                    let c = m * SIMD4<Float>(Float(x), Float(y), Float(z), 1)
                    #expect(abs(c.x) <= 1.001 && abs(c.y) <= 1.001 && c.z >= -0.001 && c.z <= 1.001)
                }
            }
        }
    }
}
