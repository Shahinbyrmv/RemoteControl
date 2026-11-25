import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var connection: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("sensitivity") private var sensitivity = 1.6
    @AppStorage("scrollSpeed") private var scrollSpeed = 1.0
    @AppStorage("momentum") private var momentum = true
    @AppStorage("haptics") private var haptics = true

    @State private var manualHost = ""
    @State private var manualPort = "50505"
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showScanner = true
                    } label: {
                        Label("QR Kodu Tara", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                    }
                } footer: {
                    Text("PC'de tepsi ikonuna sağ tıklayıp \"Bağlantı QR Kodunu Göster\"i seçin.")
                }

                Section("Bulunan bilgisayarlar") {
                    if connection.discovered.isEmpty {
                        Label("Aranıyor… (PC'de RemoteControl açık olmalı)", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(connection.discovered) { server in
                        Button {
                            connection.connect(to: server)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                VStack(alignment: .leading) {
                                    Text(server.name).foregroundStyle(.primary)
                                    Text(server.host).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if connection.current?.host == server.host && connection.state.isConnected {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("IP adresi (ör. 192.168.1.20)", text: $manualHost)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                    Button("Bağlan") {
                        let host = manualHost.trimmingCharacters(in: .whitespaces)
                        guard !host.isEmpty else { return }
                        connection.connect(to: ServerInfo(name: host, host: host,
                                                          wsPort: Int(manualPort) ?? 50505))
                        dismiss()
                    }
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Manuel bağlantı")
                }

                Section("İmleç") {
                    LabeledSlider(title: "Hız", value: $sensitivity, range: 0.5...4.0)
                    LabeledSlider(title: "Kaydırma hızı", value: $scrollSpeed, range: 0.3...3.0)
                    Toggle("Ataletli kaydırma", isOn: $momentum)
                    Toggle("Dokunsal geri bildirim", isOn: $haptics)
                }

                Section("Hareketler") {
                    GestureRow(icon: "hand.point.up.left", text: "1 parmak sürükle: imleç")
                    GestureRow(icon: "hand.tap", text: "Dokun: sol tık • İki kez dokun: çift tık")
                    GestureRow(icon: "hand.draw", text: "Çift dokun + sürükle: tut ve taşı")
                    GestureRow(icon: "hand.tap.fill", text: "2 parmak dokun: sağ tık • 3 parmak: orta tık")
                    GestureRow(icon: "arrow.up.and.down", text: "2 parmak sürükle: kaydırma")
                }

                Section {
                    Button("Kayıtlı bilgisayarı unut", role: .destructive) {
                        connection.forgetServer()
                    }
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner, onDismiss: {
            // QR ile bağlantı başladıysa ayarları da kapat, trackpad'e dön
            switch connection.state {
            case .connecting, .connected: dismiss()
            default: break
            }
        }) {
            QRScanSheet().environmentObject(connection)
        }
        .onAppear {
            if manualHost.isEmpty, let current = connection.current { manualHost = current.host }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f×", value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 0.1)
        }
    }
}

private struct GestureRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
    }
}
