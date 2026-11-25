import Foundation
import Network

/// Bonjour ile `_remotecontrol._tcp` servislerini yerel ağda arar.
final class ServerDiscovery {
    var onChange: (([ServerInfo]) -> Void)?

    private var browser: NWBrowser?
    private var restartWork: DispatchWorkItem?

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_remotecontrol._tcp", domain: "local."),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let servers = results.compactMap(ServerInfo.init(result:))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self?.onChange?(servers)
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .waiting:
                // Ağ değişimi / izin reddi: kısa süre sonra yeniden dene
                self?.scheduleRestart()
            default:
                break
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        restartWork?.cancel()
        restartWork = nil
        browser?.cancel()
        browser = nil
    }

    private func scheduleRestart() {
        guard restartWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWork = nil
            self.browser?.cancel()
            self.browser = nil
            self.start()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
