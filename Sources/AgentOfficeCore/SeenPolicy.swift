/// "Bitti, görülmedi" ne zaman kalkar: panel odakta ve uygulama önde olsa da bitiş anında kullanıcı izliyor
/// sayılmaz; ancak uygulamada bir hareket (fare, tıklama, tuş, kaydırma) ya da uygulamaya dönüş, odaktaki ve
/// görünen oturumu görüldü yapar.
public enum SeenPolicy {
    public static let finishIsWatched = false

    public static func marksSeen(appActive: Bool, officeMode: Bool, focusedVisible: Bool, unseen: Bool) -> Bool {
        appActive && !officeMode && focusedVisible && unseen
    }
}
