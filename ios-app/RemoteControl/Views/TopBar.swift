import SwiftUI

struct TopBar: View {
    @EnvironmentObject private var connection: ConnectionManager
    @Binding var keyboardActive: Bool
    @Binding var showSettings: Bool
    @Binding var showScanner: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if case .failed = connection.state { connection.retry() }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: statusColor.opacity(0.7), radius: 4)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if !connection.state.isConnected {
                BarButton(systemName: "qrcode.viewfinder") { showScanner = true }
            }

            BarButton(systemName: "slider.horizontal.3") { showSettings = true }

            BarButton(systemName: keyboardActive ? "keyboard.chevron.compact.down" : "keyboard",
                      highlighted: keyboardActive) {
                keyboardActive.toggle()
                Haptics.key()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var statusColor: Color {
        switch connection.state {
        case .connected: return .green
        case .connecting, .searching: return .orange
        case .failed, .idle: return .red
        }
    }

    private var title: String {
        switch connection.state {
        case .connected(let name): return name
        case .connecting(let name): return name
        case .searching: return "PC aranıyor…"
        case .failed: return connection.current?.name ?? "Bağlı değil"
        case .idle: return "Bağlı değil"
        }
    }

    private var subtitle: String? {
        switch connection.state {
        case .connected:
            if let ms = connection.latencyMs { return "Bağlı • \(ms) ms" }
            return "Bağlı"
        case .connecting: return "Bağlanıyor…"
        case .searching: return "Aynı Wi-Fi ağında RemoteControl sunucusu bekleniyor"
        case .failed(let reason): return "\(reason) • yeniden denemek için dokun"
        case .idle: return nil
        }
    }
}

private struct BarButton: View {
    let systemName: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(highlighted ? Color.black : Color.white.opacity(0.85))
                .frame(width: 40, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(highlighted ? Color.white : Color.white.opacity(0.09))
                )
        }
        .buttonStyle(.plain)
    }
}
