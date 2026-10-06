/// Ofisin kare hızı (spec §6): RealityKit'in kare başına sabit maliyeti olduğundan tek ayar düğmesi.
public enum FramePacing {
    public static func fps(moving: Bool, interacting: Bool, visible: Bool, mini: Bool) -> Double {
        guard visible else { return 0 }
        if mini { return 12 }
        return moving || interacting ? 24 : 12
    }
}
