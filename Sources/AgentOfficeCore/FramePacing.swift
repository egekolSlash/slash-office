/// Ofisin kare hızı (spec v4 §1): hareket ya da jest varken ekranın yenileme hızı, sadece döngü animasyonları
/// varken 12 fps, mini ofiste en fazla 12 (jest hariç), görünmezken ya da canlandırılacak bir şey yokken dur.
public enum FramePacing {
    public enum Mode: Equatable, Sendable {
        case native
        case fixed(Double)
        case paused
    }

    public static func mode(moving: Bool, interacting: Bool, animating: Bool, visible: Bool, mini: Bool) -> Mode {
        guard visible else { return .paused }
        let busy = moving || interacting
        if mini {
            // Mini ofiste köylüler en fazla 12 fps; ama jest (kaydırma, yakınlaştırma) akıcı olsun.
            if interacting { return .native }
            return busy || animating ? .fixed(12) : .paused
        }
        if busy { return .native }
        return animating ? .fixed(12) : .paused
    }
}
