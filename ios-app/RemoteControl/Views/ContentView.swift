import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connection: ConnectionManager

    @AppStorage("sensitivity") private var sensitivity = 1.6
    @AppStorage("scrollSpeed") private var scrollSpeed = 1.0
    @AppStorage("momentum") private var momentum = true

    @State private var keyboardActive = false
    @State private var showSettings = false
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(keyboardActive: $keyboardActive, showSettings: $showSettings, showScanner: $showScanner)

            // Kalan tüm yükseklik trackpad'e aittir. Klavye açılınca SwiftUI klavye güvenli alanı
            // VStack'i kısaltır; trackpad küçülür ama aktif kalmaya devam eder.
            TrackpadView(connection: connection,
                         sensitivity: sensitivity,
                         scrollSpeed: scrollSpeed,
                         momentum: momentum)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(white: 0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .overlay(TrackpadHint(connected: connection.state.isConnected).allowsHitTesting(false))
                .padding(.horizontal, 6)
                .padding(.bottom, keyboardActive ? 4 : 6)

            if keyboardActive {
                AccessoryBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .background(
            KeyCaptureRepresentable(isActive: $keyboardActive, connection: connection)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        )
        .animation(.easeOut(duration: 0.2), value: keyboardActive)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(connection)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScanSheet().environmentObject(connection)
        }
        .onChange(of: showSettings) { _, shown in
            if shown { keyboardActive = false }
        }
        .onChange(of: showScanner) { _, shown in
            if shown { keyboardActive = false }
        }
    }
}

/// Trackpad ortasında soluk ipucu.
private struct TrackpadHint: View {
    let connected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: connected ? "hand.point.up.left" : "wifi.exclamationmark")
                .font(.system(size: 28, weight: .light))
            Text(connected ? "Dokun: sol tık  •  2 parmak: sağ tık / kaydır\nÇift dokun + sürükle: tut ve taşı"
                           : "Bilgisayar bekleniyor…")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.white.opacity(0.13))
    }
}

#Preview {
    ContentView().environmentObject(ConnectionManager())
}
