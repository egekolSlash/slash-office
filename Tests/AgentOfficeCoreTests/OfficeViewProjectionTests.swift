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
