import Foundation
import Network
import UIKit

enum ConnectionState: Equatable {
    case idle
    case searching
    case connecting(String)
    case connected(String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Windows sunucusuyla iletişim.
/// - WebSocket (TCP, Nagle kapalı): tık, sürükleme, kaydırma, klavye
/// - UDP: fare hareketi (17 baytlık ikili paket)
/// Tüm durum ana kuyrukta tutulur; dokunma olayları da ana kuyrukta geldiği için kilit gerekmez.
final class ConnectionManager: ObservableObject {
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discovered: [ServerInfo] = []
    @Published private(set) var latencyMs: Int?
    @Published private(set) var current: ServerInfo?

    private let discovery = ServerDiscovery()
    private var ws: NWConnection?
    private var udp: NWConnection?
    private var udpReady = false
    private var session: UInt32 = 0
    private var seq: UInt32 = 0
    private var generation = 0          // eski bağlantıların geç gelen callback'lerini yok saymak için
    private var isActive = false
    private var autoReconnect = true
    private var attempt = 0
    private var reconnectWork: DispatchWorkItem?
    private var pingTimer: Timer?
    private var lastPong = Date()

    init() {
        discovery.onChange = { [weak self] servers in self?.handleDiscovery(servers) }
    }

    // MARK: - Yaşam döngüsü

    func start() {
        guard !isActive else { return }
        isActive = true
        autoReconnect = true
        discovery.start()
        connectToBestTarget()
    }

    func stop() {
        isActive = false
        reconnectWork?.cancel()
        discovery.stop()
        teardown()
        state = .idle
    }

    /// Kullanıcı tarafından seçilen sunucuya bağlan (QR, liste veya manuel IP).
    func connect(to server: ServerInfo, remember: Bool = true) {
        if remember { server.save() }
        autoReconnect = true
        attempt = 0
        open(server)
    }

    func retry() {
        autoReconnect = true
        attempt = 0
        connectToBestTarget()
    }

    func forgetServer() {
        ServerInfo.clearSaved()
        teardown()
        state = .searching
        connectToBestTarget()
    }

    func handleURL(_ url: URL) {
        guard let server = ServerInfo(url: url) else { return }
        connect(to: server)
    }

    // MARK: - Hedef seçimi

    private func handleDiscovery(_ servers: [ServerInfo]) {
        discovered = servers
        guard isActive else { return }
        switch state {
        case .idle, .searching, .failed:
            if autoReconnect, reconnectWork == nil { connectToBestTarget() }
        default:
            break
        }
    }

    /// Kayıtlı sunucu (IP'si değiştiyse Bonjour'dan tazelenmiş haliyle) > ilk bulunan sunucu.
    private func bestTarget() -> ServerInfo? {
        if var saved = ServerInfo.loadSaved() {
            if let fresh = discovered.first(where: { $0.name == saved.name }) {
                saved.host = fresh.host
                saved.wsPort = fresh.wsPort
                saved.udpPort = fresh.udpPort
            } else if attempt >= 2, let any = discovered.first {
                return any
            }
            return saved
        }
        return discovered.first
    }

    private func connectToBestTarget() {
        reconnectWork?.cancel()
        reconnectWork = nil
        guard isActive else { return }
        guard let target = bestTarget() else {
            teardown()
            state = .searching
            return
        }
        open(target)
    }

    // MARK: - Bağlantı

    private func open(_ server: ServerInfo) {
        teardown()
        generation += 1
        let gen = generation
        current = server
        state = .connecting(server.name)

        guard let url = URL(string: "ws://\(server.host):\(server.wsPort)") else {
            state = .failed("Geçersiz adres")
            return
        }

        let params = NWParameters.tcp
        params.serviceClass = .responsiveData
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.connectionTimeout = 4
        }
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let conn = NWConnection(to: .url(url), using: params)
        ws = conn
        conn.stateUpdateHandler = { [weak self] newState in
            guard let self, gen == self.generation else { return }
            switch newState {
            case .ready:
                self.sendJSON([
                    "t": "hello",
                    "v": 1,
                    "name": UIDevice.current.name,
                    "token": server.token ?? "",
                ], force: true)
                self.receive(on: conn, gen: gen)
            case .waiting(let error), .failed(let error):
                self.handleDrop(reason: Self.describe(error))
            default:
                break
            }
        }
        conn.start(queue: .main)
    }

    private func receive(on conn: NWConnection, gen: Int) {
        conn.receiveMessage { [weak self] data, context, _, error in
            guard let self, gen == self.generation else { return }
            if let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata, meta.opcode == .close {
                self.handleClose(code: meta.closeCode)
                return
            }
            if let data, !data.isEmpty {
                self.handleMessage(data)
            }
            if let error {
                self.handleDrop(reason: Self.describe(error))
                return
            }
            self.receive(on: conn, gen: gen)
        }
    }

    private func handleMessage(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["t"] as? String else { return }
        switch type {
        case "welcome":
            guard var server = current else { return }
            session = UInt32(truncatingIfNeeded: (obj["session"] as? NSNumber)?.int64Value ?? 0)
            seq = 0
            if let name = obj["name"] as? String { server.name = name }
            if let udpPort = obj["udp"] as? Int { server.udpPort = udpPort }
            if server.token == nil, let saved = ServerInfo.loadSaved(), saved.name == server.name {
                server.token = saved.token
            }
            current = server
            server.save()   // son bağlanılan PC, bir sonraki açılışta ilk denenir
            attempt = 0
            lastPong = Date()
            openUDP(server)
            startPing()
            state = .connected(server.name)
            Haptics.success()
        case "pong":
            lastPong = Date()
            if let ts = obj["ts"] as? Double {
                latencyMs = Int(((Date().timeIntervalSince1970 - ts) * 1000).rounded())
            }
        case "error":
            if (obj["code"] as? String) == "auth" {
                autoReconnect = false
                teardown()
                state = .failed("Yetki yok – PC'deki QR kodunu taratın")
            }
        default:
            break
        }
    }

    private func handleClose(code: NWProtocolWebSocket.CloseCode) {
        switch code {
        case .privateCode(4000):
            autoReconnect = false
            teardown()
            state = .failed("Başka bir cihaz bağlandı")
        case .privateCode(4003):
            autoReconnect = false
            teardown()
            state = .failed("Yetki yok – PC'deki QR kodunu taratın")
        default:
            handleDrop(reason: "Bağlantı kapandı")
        }
    }

    private func handleDrop(reason: String) {
        teardown()
        guard isActive else { state = .idle; return }
        state = .failed(reason)
        guard autoReconnect else { return }
        attempt += 1
        let delay = min(Double(attempt), 5.0)
        let work = DispatchWorkItem { [weak self] in self?.connectToBestTarget() }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func teardown() {
        generation += 1
        pingTimer?.invalidate()
        pingTimer = nil
        ws?.cancel()
        ws = nil
        udp?.cancel()
        udp = nil
        udpReady = false
        session = 0
        latencyMs = nil
    }

    private func openUDP(_ server: ServerInfo) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: server.udpPort)) else { return }
        let params = NWParameters.udp
        params.serviceClass = .interactiveVoice   // Wi-Fi WMM: en yüksek öncelik kuyruğu
        let conn = NWConnection(host: NWEndpoint.Host(server.host), port: port, using: params)
        let gen = generation
        conn.stateUpdateHandler = { [weak self] st in
            guard let self, gen == self.generation else { return }
            if case .ready = st { self.udpReady = true } else if case .failed = st { self.udpReady = false }
        }
        conn.start(queue: .main)
        udp = conn
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastPong) > 6.5 {
                self.handleDrop(reason: "Yanıt yok")
                return
            }
            self.sendJSON(["t": "ping", "ts": Date().timeIntervalSince1970])
        }
    }

    // MARK: - Gönderim

    private func sendJSON(_ object: [String: Any], force: Bool = false) {
        guard let ws, force || state.isConnected,
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [meta])
        ws.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    func move(dx: CGFloat, dy: CGFloat) {
        guard state.isConnected else { return }
        guard udpReady, let udp else {
            sendJSON(["t": "move", "dx": Double(dx), "dy": Double(dy)])   // UDP hazır değilse yedek yol
            return
        }
        seq &+= 1
        var packet = Data(capacity: 17)
        packet.append(0x4D) // "M"
        withUnsafeBytes(of: session.littleEndian) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: seq.littleEndian) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: Float32(dx).bitPattern.littleEndian) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: Float32(dy).bitPattern.littleEndian) { packet.append(contentsOf: $0) }
        udp.send(content: packet, completion: .idempotent)
    }

    func click(_ button: String = "left", count: Int = 1) {
        sendJSON(["t": "click", "b": button, "n": count])
    }

    func setButton(_ button: String, down: Bool) {
        sendJSON(["t": down ? "down" : "up", "b": button])
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        sendJSON(["t": "scroll", "dx": Double(dx), "dy": Double(dy)])
    }

    func scrollEnd() {
        sendJSON(["t": "scroll_end"])
    }

    func text(_ string: String) {
        sendJSON(["t": "text", "s": string])
    }

    func key(_ name: String) {
        sendJSON(["t": "key", "k": name])
    }

    func combo(_ keys: [String]) {
        sendJSON(["t": "combo", "k": keys])
    }

    // MARK: - Yardımcı

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .ECONNREFUSED:
            return "PC'de sunucu çalışmıyor"
        case .posix(let code) where code == .ETIMEDOUT || code == .EHOSTUNREACH || code == .ENETUNREACH:
            return "PC'ye ulaşılamıyor"
        case .dns:
            return "Adres çözümlenemedi"
        default:
            return "Bağlantı hatası"
        }
    }
}
