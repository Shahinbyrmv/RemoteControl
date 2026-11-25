import SwiftUI

@main
struct RemoteControlApp: App {
    @StateObject private var connection = ConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connection)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // PC'deki QR kodu iPhone Kamera ile taranınca: remotecontrol://connect?...
                    connection.handleURL(url)
                }
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    connection.start()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                connection.start()
            case .background:
                // iOS arka planda soketleri askıya alır; temiz kapat ki PC "bağlantı kesildi" desin
                connection.stop()
            default:
                break
            }
        }
    }
}
