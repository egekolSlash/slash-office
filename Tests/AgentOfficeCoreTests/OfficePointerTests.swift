import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct OfficePointerTests {
    @Test func trackpadScrollPans() {
        #expect(OfficePointer.scroll(deltaX: 3, deltaY: -5, precise: true, gestureDevice: true, command: false, shift: false)
                == .pan(dx: 3, dy: -5))
    }

    @Test func mouseWheelZoomsAtCursor() {
        let up = OfficePointer.scroll(deltaX: 0, deltaY: 1, precise: false, gestureDevice: false, command: false, shift: false)
        let down = OfficePointer.scroll(deltaX: 0, deltaY: -1, precise: false, gestureDevice: false, command: false, shift: false)
        guard case .zoom(let a) = up, case .zoom(let b) = down else { Issue.record("zoom bekleniyordu"); return }
        #expect(a > 1 && b < 1)
        #expect(abs(a * b - 1) < 1e-9)
        // Yumuşak kaydırmalı fareler piksel delta verir: aynı yön, daha küçük adım.
        let smooth = OfficePointer.scroll(deltaX: 0, deltaY: 10, precise: true, gestureDevice: false, command: false, shift: false)
        #expect(smooth == .zoom(factor: exp(0.1)))
    }

    @Test func shiftWheelPansAndCommandAlwaysZooms() {
        #expect(OfficePointer.scroll(deltaX: 2, deltaY: 0, precise: false, gestureDevice: false, command: false, shift: true)
                == .pan(dx: 20, dy: 0))
        #expect(OfficePointer.scroll(deltaX: 0, deltaY: 4, precise: true, gestureDevice: true, command: true, shift: false)
                == .zoom(factor: exp(0.04)))
    }

    @Test func smallMovesStayClicks() {
        #expect(!OfficePointer.isDrag(fromX: 10, fromY: 10, toX: 12, toY: 12))
        #expect(OfficePointer.isDrag(fromX: 10, fromY: 10, toX: 14, toY: 10))
    }
}
