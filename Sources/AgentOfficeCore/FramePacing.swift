/// Ofisin kare hızı (spec v4 §1): hareket ya da jest varken ekranın yenileme hızı, sadece döngü animasyonları
/// varken 12 fps, mini ofiste en fazla 12 (jest hariç), görünmezken ya da canlandırılacak bir şey yokken dur.
/// Enerji tasarrufu kapalıyken (`saving: false`) görünür ve canlı ofis her zaman ekran hızında, mini dahil.
public enum FramePacing {
    public enum Mode: Equatable, Sendable {
        case native
        case fixed(Double)
        case paused
    }

    /// `moving`: yürüyen köylü; `acting`: yerinde tek seferlik hareket, oturma/kalkma ya da klip geçişi.
    public static func mode(moving: Bool, acting: Bool = false, interacting: Bool, animating: Bool,
                            visible: Bool, mini: Bool, saving: Bool = true) -> Mode {
        guard visible else { return .paused }
        let busy = moving || interacting
        if !saving { return busy || acting || animating ? .native : .paused }
        if mini {
            // Mini ofiste köylüler en fazla 12 fps; ama jest (kaydırma, yakınlaştırma) akıcı olsun.
            if interacting { return .native }
            return busy || acting || animating ? .fixed(12) : .paused
        }
        if busy { return .native }
        // Yerinde hareket: klipler 24 fps, 30 fps'te akıcı; native'e gerek yok.
        if acting { return .fixed(30) }
        return animating ? .fixed(12) : .paused
    }
}
