import UIKit

/// Hafif dokunsal geri bildirim. Ayarlardan kapatılabilir.
enum Haptics {
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true
    }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare()
        medium.prepare()
        rigid.prepare()
    }

    static func tap() { fire(light, intensity: 0.7) }
    static func rightClick() { fire(rigid, intensity: 0.8) }
    static func dragStart() { fire(medium, intensity: 0.9) }
    static func key() { fire(light, intensity: 0.5) }

    static func success() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    private static func fire(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        guard enabled else { return }
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }
}
