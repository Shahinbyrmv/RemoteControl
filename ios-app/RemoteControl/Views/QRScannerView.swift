import SwiftUI
import VisionKit

/// PC'deki "Bağlantı QR Kodunu Göster" penceresini uygulama içinden tarar.
struct QRScanSheet: View {
    @EnvironmentObject private var connection: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if scannerAvailable {
                    QRScannerView { payload in
                        handle(payload)
                    }
                    .ignoresSafeArea()

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text("Kamera kullanılamıyor")
                            .font(.headline)
                        Text("Ayarlar → RemoteControl → Kamera iznini açın.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Ayarları Aç") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }

                VStack {
                    Spacer()
                    Text(message ?? "PC'de tepsi ikonuna sağ tıklayın →\n\"Bağlantı QR Kodunu Göster\"")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
                .allowsHitTesting(false)
            }
            .navigationTitle("QR ile Bağlan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }

    /// true döner: kod kabul edildi (tarayıcı durur).
    private func handle(_ payload: String) -> Bool {
        guard let url = URL(string: payload), let server = ServerInfo(url: url) else {
            message = "Bu bir RemoteControl QR kodu değil"
            Haptics.rightClick()
            return false
        }
        connection.connect(to: server)
        Haptics.success()
        dismiss()
        return true
    }
}

/// VisionKit DataScannerViewController sarmalayıcısı (yalnızca QR).
struct QRScannerView: UIViewControllerRepresentable {
    /// Kod kabul edilirse true döndürmeli; false dönerse tarama devam eder.
    let onCode: (String) -> Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Bool
        private var accepted = false
        private var lastRejected: String?

        init(onCode: @escaping (String) -> Bool) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !accepted else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let payload = barcode.payloadStringValue,
                      payload != lastRejected else { continue }
                if onCode(payload) {
                    accepted = true
                    dataScanner.stopScanning()
                } else {
                    lastRejected = payload
                }
                return
            }
        }
    }
}
