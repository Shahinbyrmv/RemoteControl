import SwiftUI
import UIKit

/// Görünmez klavye alıcısı. UIKeyInput sayesinde her tuş anında yakalanır:
/// metin alanı yok, otomatik düzeltme yok, Gönder tuşu beklenmez.
/// `hasText` hep true döner; böylece boş alanda bile Sil (⌫) tuşu çalışır.
final class KeyCaptureView: UIView, UIKeyInput {
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    // MARK: UITextInputTraits – tahmin/düzeltme/akıllı noktalama tamamen kapalı
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var inlinePredictionType: UITextInlinePredictionType = .no
    var keyboardType: UIKeyboardType = .default
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var returnKeyType: UIReturnKeyType = .default
    var enablesReturnKeyAutomatically = false

    override var canBecomeFirstResponder: Bool { true }

    var hasText: Bool { true }

    func insertText(_ text: String) {
        onText?(text)   // "\n" (Return) sunucuda Enter'a çevrilir
    }

    func deleteBackward() {
        onDelete?()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }
}

struct KeyCaptureRepresentable: UIViewRepresentable {
    @Binding var isActive: Bool
    let connection: ConnectionManager

    func makeUIView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: KeyCaptureView, context: Context) {
        let conn = connection
        view.onText = { text in
            conn.text(text)
            Haptics.key()
        }
        view.onDelete = {
            conn.key("backspace")
            Haptics.key()
        }
        let binding = $isActive
        view.onFocusChange = { focused in
            if binding.wrappedValue != focused {
                DispatchQueue.main.async { binding.wrappedValue = focused }
            }
        }

        let shouldFocus = isActive
        DispatchQueue.main.async {
            if shouldFocus, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !shouldFocus, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }
}
