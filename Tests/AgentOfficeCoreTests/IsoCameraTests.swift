import Testing
@testable import AgentOfficeCore

@Suite struct IsoCameraTests {
    let size = (width: 800.0, height: 600.0)

    @Test func centerProjectsToViewCenter() {
        let camera = IsoCamera(center: [1, 0, 2], scale: 3)
        let p = camera.project([1, 0, 2], viewSize: size)
        #expect(abs(p.x - 400) < 0.001 && abs(p.y - 300) < 0.001)
    }

    @Test func axesMoveInIsometricDirections() {
        let camera = IsoCamera(center: .zero, scale: 3)
        let origin = camera.project(.zero, viewSize: size)
        let up = camera.project([0, 1, 0], viewSize: size)
        let nextColumn = camera.project([1, 0, 0], viewSize: size)
        let nextRow = camera.project([0, 0, 1], viewSize: size)
        #expect(up.y < origin.y && abs(up.x - origin.x) < 0.001)
        #expect(nextColumn.x > origin.x && nextColumn.y > origin.y)
        #expect(nextRow.x < origin.x && nextRow.y > origin.y)
    }

    @Test func scaleIsHalfOfVisibleHeight() {
        // Kamera yukarı vektörü boyunca `scale` kadar yukarıdaki nokta görünümün üst kenarına düşer.
        let camera = IsoCamera(center: .zero, scale: 2)
        let top = camera.project(IsoCamera.screenUp * 2, viewSize: size)
        #expect(abs(top.y) < 0.001)
    }

    @Test func fittingKeepsPreviousFramingFormula() {
        let camera = IsoCamera.fitting(columns: 2, rows: 3, tileSize: 1.2)
        #expect(abs(camera.scale - max((6 * 0.41 + 1.4) / 1.6, 6 * 0.71 / 1.7)) < 0.0001)
        #expect(camera.center == SIMD3<Float>(0.6, 0.3, 1.2))
        let empty = IsoCamera.fitting(columns: 0, rows: 0, tileSize: 1.2)
        #expect(empty.scale > 0)
    }
}
