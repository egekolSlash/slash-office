/// Çalıştırmalar arasında sabit kalan hash (Swift'in `hashValue`'su her çalıştırmada değişir).
public enum StableHash {
    public static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// splitmix64 son karıştırıcısı: FNV'nin üst bitleri benzer metinlerde (ör. sadece son harfi farklı kimlikler)
    /// az değişir; ayrı bitlerden özellik seçerken önce karıştırılır.
    public static func mixed(_ text: String) -> UInt64 {
        var z = fnv1a(text) &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
