import Foundation
import Network

/// Bağlanılabilir bir Windows sunucusu (mDNS keşfi, QR kodu veya manuel giriş).
struct ServerInfo: Codable, Equatable, Identifiable, Hashable {
    var name: String
    var host: String
    var wsPort: Int = 50505
    var udpPort: Int = 50506
    var token: String? = nil

    var id: String { "\(name)@\(host):\(wsPort)" }

    init(name: String, host: String, wsPort: Int = 50505, udpPort: Int = 50506, token: String? = nil) {
        self.name = name
        self.host = host
        self.wsPort = wsPort
        self.udpPort = udpPort
        self.token = token
    }

    /// remotecontrol://connect?host=..&ws=..&udp=..&name=..&token=..&v=1
    init?(url: URL) {
        guard url.scheme?.lowercased() == "remotecontrol",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        var q: [String: String] = [:]
        for item in items { q[item.name] = item.value }
        guard let host = q["host"], !host.isEmpty else { return nil }
        self.init(name: q["name"] ?? host,
                  host: host,
                  wsPort: Int(q["ws"] ?? "") ?? 50505,
                  udpPort: Int(q["udp"] ?? "") ?? 50506,
                  token: q["token"])
    }

    /// Bonjour sonucundan (TXT kaydı: name, ip, ws, udp).
    init?(result: NWBrowser.Result) {
        guard case let .service(serviceName, _, _, _) = result.endpoint,
              case let .bonjour(txt) = result.metadata
        else { return nil }
        let dict = txt.dictionary
        guard let ip = dict["ip"], !ip.isEmpty else { return nil }
        self.init(name: dict["name"] ?? serviceName,
                  host: ip,
                  wsPort: Int(dict["ws"] ?? "") ?? 50505,
                  udpPort: Int(dict["udp"] ?? "") ?? 50506)
    }

    // MARK: - Kalıcı kayıt

    private static let storageKey = "savedServer"

    static func loadSaved() -> ServerInfo? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ServerInfo.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
