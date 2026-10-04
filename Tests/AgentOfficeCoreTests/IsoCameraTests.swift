import Testing
import simd
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

    @Test func fittingCentersGridAndHandlesEmpty() {
        let camera = IsoCamera.fitting(columns: 2, rows: 3, tileSize: 1.2, aspect: 1.5)
        #expect(camera.center == SIMD3<Float>(0.6, 0.3, 1.2))
        let empty = IsoCamera.fitting(columns: 0, rows: 0, tileSize: 1.2, aspect: 1.5)
        #expect(empty.scale > 0)
    }

    @Test(arguments: [(320.0, 500.0), (240.0, 400.0), (1200.0, 800.0), (900.0, 300.0)])
    func tilesAndLabelsStayInsideView(width: Double, height: Double) {
        // Çalışma modundaki dar ve uzun sağ sütun dahil: karo köşeleri ve başlık kutuları görünümün içinde kalmalı.
        let view = (width: width, height: height)
        for (columns, rows) in [(3, 2), (1, 6), (4, 3), (1, 1)] {
            let camera = IsoCamera.fitting(columns: columns, rows: rows, tileSize: 1.2, aspect: width / height)
            for column in 0..<columns {
                for row in 0..<rows {
                    let x = Float(column) * 1.2, z = Float(row) * 1.2
                    var points: [SIMD3<Float>] = [[x - 0.6, 0, z - 0.6], [x + 0.6, 0, z - 0.6], [x - 0.6, 0, z + 0.6], [x + 0.6, 0, z + 0.6]]
                    points += [[x, IsoCamera.labelHeight, z]]
                    for point in points {
                        let p = camera.project(point, viewSize: view)
                        #expect(p.x >= 0 && p.x <= width && p.y >= 0 && p.y <= height,
                                "grid \(columns)x\(rows) view \(width)x\(height) point \(point) -> \(p)")
                    }
                    // Başlık kutusu yarı genişliği ve `?` balonu için yatay ve dikey pay.
                    let label = camera.project([x, IsoCamera.labelHeight, z], viewSize: view)
                    let font = min(max(height / (2 * Double(camera.scale)) * 0.13, 9), 15)
                    #expect(label.x - font * 3.5 >= 0 && label.x + font * 3.5 <= width && label.y - font * 3.6 >= 0,
                            "label box grid \(columns)x\(rows) view \(width)x\(height)")
                }
            }
        }
    }

    @Test func unprojectInvertsProjectOnAGivenHeight() {
        let camera = IsoCamera(center: [1.2, 0.3, 0.6], scale: 2.5)
        for point in [SIMD3<Float>(0, 0, 0), [2.4, 0, 1.2], [1.1, 0.4, -0.3]] {
            let screen = camera.project(point, viewSize: size)
            let back = camera.unproject(x: screen.x, y: screen.y, viewSize: size, height: point.y)
            #expect(simd_distance(back, point) < 0.001)
        }
    }

    @Test func tileHitPrefersDeskHeightThenFloor() {
        let tiles = [TilePlacement(id: "a", column: 0, row: 0, project: "/p"), TilePlacement(id: "b", column: 1, row: 0, project: "/p")]
        let camera = IsoCamera.fitting(columns: 2, rows: 1, tileSize: 1.2, aspect: 800.0 / 600.0)
        // Karonun masa yüksekliğindeki merkezine tıklama o karoyu seçer.
        let onB = camera.project([1.2, 0.45, 0], viewSize: size)
        #expect(camera.tile(atX: onB.x, y: onB.y, viewSize: size, tiles: tiles, tileSize: 1.2) == "b")
        let onA = camera.project([0, 0.02, 0], viewSize: size)
        #expect(camera.tile(atX: onA.x, y: onA.y, viewSize: size, tiles: tiles, tileSize: 1.2) == "a")
        // Boş alana tıklama hiçbir şey seçmez.
        #expect(camera.tile(atX: 2, y: 2, viewSize: size, tiles: tiles, tileSize: 1.2) == nil)
    }

    @Test func clickOnTitleLabelSelectsItsTile() {
        // Önde (row 1) ve arkada (row 0) iki karo: öndekinin başlığı ekranda arkadakinin alanına düşer.
        let tiles = [TilePlacement(id: "back", column: 0, row: 0, project: "/p"), TilePlacement(id: "front", column: 0, row: 1, project: "/p")]
        let camera = IsoCamera.fitting(columns: 1, rows: 2, tileSize: 1.2, aspect: 800.0 / 600.0)
        let label = camera.project([0, IsoCamera.labelHeight, 1.2], viewSize: size)
        let labelBox = (width: 60.0, height: 30.0)
        #expect(camera.tile(atX: label.x, y: label.y, viewSize: size, tiles: tiles, tileSize: 1.2, labelBox: labelBox) == "front")
        #expect(camera.tile(atX: label.x + 25, y: label.y - 12, viewSize: size, tiles: tiles, tileSize: 1.2, labelBox: labelBox) == "front")
        // Başlık kutusunun dışı eskisi gibi geometriye göre seçilir.
        let backDesk = camera.project([0, 0.45, 0], viewSize: size)
        #expect(camera.tile(atX: backDesk.x, y: backDesk.y, viewSize: size, tiles: tiles, tileSize: 1.2, labelBox: labelBox) == "back")
    }
}
