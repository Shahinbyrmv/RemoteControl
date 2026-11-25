import SwiftUI
import UIKit

/// Ham UITouch olaylarıyla çalışan trackpad yüzeyi.
/// SwiftUI jestleri yerine dokunuş durum makinesi kullanılır: parmak sayısını kesin ayırt eder,
/// gecikme eklemez ve "çift dokun + sürükle" gibi birleşik hareketleri destekler.
///
///  - 1 parmak sürükle          → imleç hareketi
///  - 1 parmak dokun            → sol tık
///  - Dokun + hemen basılı sürükle → sol tuş basılı sürükleme (drag & drop)
///  - Hızlı iki dokunuş         → çift tık
///  - 2 parmak dokun            → sağ tık
///  - 2 parmak sürükle          → kaydırma (ataletli)
///  - 3 parmak dokun            → orta tık
final class TrackpadSurface: UIView {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onScrollEnd: (() -> Void)?
    var onClick: ((String, Int) -> Void)?
    var onButton: ((String, Bool) -> Void)?

    var sensitivity: CGFloat = 1.6
    var scrollSpeed: CGFloat = 1.0
    var momentumEnabled = true

    private enum Mode { case idle, pointer, dragging, scrolling }

    private static let tapMaxDuration: TimeInterval = 0.25
    private static let tapMaxTravel: CGFloat = 10
    private static let doubleTapWindow: TimeInterval = 0.22
    private static let dragStartTravel: CGFloat = 4

    private var mode: Mode = .idle
    private var activeTouches = Set<UITouch>()
    private var maxTouches = 0
    private var sequenceStart: TimeInterval = 0
    private var travel: CGFloat = 0

    // Tap-to-click + çift dokunup sürükleme
    private var pendingClick: DispatchWorkItem?
    private var owedClick = false          // önceki dokunuşun tıkı ertelendi; bu dokunuş sürüklemeye dönebilir
    private var bufferedMove = CGPoint.zero

    // Kaydırma ataleti
    private var velocity = CGPoint.zero
    private var lastScrollTime: TimeInterval = 0
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    // MARK: - Dokunuşlar

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopMomentum()
        if activeTouches.isEmpty {
            mode = .idle
            maxTouches = 0
            travel = 0
            bufferedMove = .zero
            sequenceStart = CACurrentMediaTime()
            if let pending = pendingClick {
                // Önceki dokunuşun tıkı henüz gönderilmedi: bu dokunuş çift tık veya sürükleme olabilir
                pending.cancel()
                pendingClick = nil
                owedClick = true
            }
            Haptics.prepare()
        }
        activeTouches.formUnion(touches)
        maxTouches = max(maxTouches, activeTouches.count)

        if activeTouches.count >= 2 {
            if owedClick { flushOwedClick() }
            if mode == .dragging { finishDrag() }
            if mode == .pointer { mode = .idle }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let moving = touches.filter { activeTouches.contains($0) }
        guard !moving.isEmpty else { return }

        if maxTouches == 1, let touch = moving.first {
            let d = delta(of: touch)
            travel += hypot(d.x, d.y)
            handleSingleFinger(d)
        } else if activeTouches.count >= 2 {
            var sum = CGPoint.zero
            for touch in moving {
                let d = delta(of: touch)
                sum.x += d.x
                sum.y += d.y
            }
            let n = CGFloat(max(activeTouches.count, 1))
            let avg = CGPoint(x: sum.x / n, y: sum.y / n)
            travel += hypot(avg.x, avg.y)
            if mode == .scrolling || travel > Self.tapMaxTravel {
                mode = .scrolling
                emitScroll(avg)
            }
        }
        // Kaydırma sonrası tek parmak kalırsa imleç oynamasın (yanlışlıkla hareket önlenir)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        guard activeTouches.isEmpty else { return }
        finishSequence(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        guard activeTouches.isEmpty else { return }
        finishSequence(cancelled: true)
    }

    // MARK: - Durum makinesi

    private func handleSingleFinger(_ d: CGPoint) {
        switch mode {
        case .idle:
            if owedClick {
                // Dokun + basılı sürükle: küçük eşiği aşınca sol tuşu bas
                bufferedMove.x += d.x
                bufferedMove.y += d.y
                if travel > Self.dragStartTravel {
                    owedClick = false
                    mode = .dragging
                    onButton?("left", true)
                    Haptics.dragStart()
                    emitMove(bufferedMove)
                    bufferedMove = .zero
                }
            } else {
                mode = .pointer
                emitMove(d)
            }
        case .pointer, .dragging:
            emitMove(d)
        case .scrolling:
            break
        }
    }

    private func finishSequence(cancelled: Bool) {
        let duration = CACurrentMediaTime() - sequenceStart
        let isTap = !cancelled && duration < Self.tapMaxDuration && travel < Self.tapMaxTravel

        switch mode {
        case .dragging:
            finishDrag()
        case .scrolling:
            if !cancelled && momentumEnabled && shouldStartMomentum() {
                startMomentum()
            } else {
                onScrollEnd?()
            }
        case .idle, .pointer:
            if isTap {
                switch maxTouches {
                case 1:
                    if owedClick {
                        owedClick = false
                        onClick?("left", 2)
                        Haptics.tap()
                    } else {
                        scheduleClick()
                    }
                case 2:
                    onClick?("right", 1)
                    Haptics.rightClick()
                case 3:
                    onClick?("middle", 1)
                    Haptics.rightClick()
                default:
                    break
                }
            }
        }

        if owedClick { flushOwedClick() }
        mode = .idle
        maxTouches = 0
    }

    /// Tıkı çift dokunma penceresi kadar ertele: ikinci dokunuş gelirse çift tık / sürükleme olur.
    private func scheduleClick() {
        Haptics.tap()   // geri bildirim hemen, tık penceresi bitince gönderilir
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingClick = nil
            self.onClick?("left", 1)
        }
        pendingClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleTapWindow, execute: work)
    }

    private func flushOwedClick() {
        owedClick = false
        onClick?("left", 1)
    }

    private func finishDrag() {
        onButton?("left", false)
        Haptics.tap()
        mode = .idle
    }

    // MARK: - Çıkış

    private func emitMove(_ d: CGPoint) {
        guard d.x != 0 || d.y != 0 else { return }
        onMove?(d.x * sensitivity, d.y * sensitivity)
    }

    private func emitScroll(_ d: CGPoint) {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastScrollTime, 1.0 / 240.0), 0.1)
        lastScrollTime = now
        let instant = CGPoint(x: d.x / dt, y: d.y / dt)
        velocity = CGPoint(x: velocity.x * 0.5 + instant.x * 0.5, y: velocity.y * 0.5 + instant.y * 0.5)
        onScroll?(d.x * scrollSpeed, d.y * scrollSpeed)
    }

    private func delta(of touch: UITouch) -> CGPoint {
        let now = touch.location(in: self)
        let prev = touch.previousLocation(in: self)
        return CGPoint(x: now.x - prev.x, y: now.y - prev.y)
    }

    // MARK: - Atalet

    private func shouldStartMomentum() -> Bool {
        CACurrentMediaTime() - lastScrollTime < 0.06 && hypot(velocity.x, velocity.y) > 180
    }

    private func startMomentum() {
        stopMomentum(notify: false)
        lastFrameTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(momentumStep(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func momentumStep(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = min(max(now - lastFrameTime, 1.0 / 120.0), 1.0 / 30.0)
        lastFrameTime = now
        let decay = pow(0.94, dt * 60)
        velocity = CGPoint(x: velocity.x * decay, y: velocity.y * decay)
        if hypot(velocity.x, velocity.y) < 25 {
            stopMomentum()
            return
        }
        onScroll?(velocity.x * dt * scrollSpeed, velocity.y * dt * scrollSpeed)
    }

    private func stopMomentum(notify: Bool = true) {
        guard let link = displayLink else { return }
        link.invalidate()
        displayLink = nil
        velocity = .zero
        if notify { onScrollEnd?() }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { stopMomentum() }
    }
}

/// SwiftUI sarmalayıcı.
struct TrackpadView: UIViewRepresentable {
    let connection: ConnectionManager
    var sensitivity: Double
    var scrollSpeed: Double
    var momentum: Bool

    func makeUIView(context: Context) -> TrackpadSurface {
        let view = TrackpadSurface()
        configure(view)
        return view
    }

    func updateUIView(_ view: TrackpadSurface, context: Context) {
        configure(view)
    }

    private func configure(_ view: TrackpadSurface) {
        let conn = connection
        view.sensitivity = CGFloat(sensitivity)
        view.scrollSpeed = CGFloat(scrollSpeed)
        view.momentumEnabled = momentum
        view.onMove = { conn.move(dx: $0, dy: $1) }
        view.onScroll = { conn.scroll(dx: $0, dy: $1) }
        view.onScrollEnd = { conn.scrollEnd() }
        view.onClick = { conn.click($0, count: $1) }
        view.onButton = { conn.setButton($0, down: $1) }
    }
}
