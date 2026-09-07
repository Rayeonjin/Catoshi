import Foundation

/// Thread-safe by construction: all mutable socket/reconnect state is serialized on
/// `stateQueue`; callbacks are installed once during model initialization.
final class BinanceTickerClient: @unchecked Sendable {
    var onTicker: ((Double, Double) -> Void)?
    var onState: ((SocketConnectionState) -> Void)?

    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "Catoshi.BinanceSocket", qos: .utility)
    private let decoder = JSONDecoder()
    private var task: URLSessionWebSocketTask?
    private var reconnectWorkItem: DispatchWorkItem?
    private var connectionID = UUID()
    private var lastMessageAt = Date.distantPast
    private var lastPingAt = Date.distantPast
    private var pingInFlight = false
    private var retryAttempt = 0
    private var emittedState: SocketConnectionState?
    private var networkAvailable = true
    private let endpoints = [
        "wss://data-stream.binance.com/ws/btcusdt@ticker",
        "wss://stream.binance.com:9443/ws/btcusdt@ticker"
    ]

    init() {
        session = URLSession(configuration: CatoshiNetworkRuntime.publicWebSocketConfiguration())
    }

    func start() {
        stateQueue.async { [weak self] in
            self?.connectLocked(resetBackoff: true)
        }
    }

    func setNetworkAvailable(_ available: Bool) {
        stateQueue.async { [weak self] in
            guard let self, self.networkAvailable != available else { return }
            self.networkAvailable = available
            if available {
                self.connectLocked(resetBackoff: true)
            } else {
                self.suspendLocked()
            }
        }
    }

    func reconnectNow() {
        stateQueue.async { [weak self] in
            guard let self, self.networkAvailable else { return }
            self.connectLocked(resetBackoff: true)
        }
    }

    func stop() {
        stateQueue.sync {
            networkAvailable = false
            suspendLocked()
        }
        session.invalidateAndCancel()
    }

    private func connectLocked(resetBackoff: Bool) {
        guard networkAvailable else {
            suspendLocked()
            return
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        // Rotate the generation before cancelling so callbacks from the old task are ignored.
        let newID = UUID()
        connectionID = newID
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        if resetBackoff { retryAttempt = 0 }
        emitStateLocked(.connecting)

        // The standard-TLS endpoint is first because some corporate/home networks block :9443.
        let endpointIndex = retryAttempt % endpoints.count
        guard let url = URL(string: endpoints[endpointIndex]) else {
            emitStateLocked(.disconnected)
            return
        }
        let socket = session.webSocketTask(with: url)
        task = socket
        lastMessageAt = Date()
        lastPingAt = .distantPast
        pingInFlight = false
        socket.resume()
        receive(on: socket, id: newID)
    }

    private func receive(on socket: URLSessionWebSocketTask, id: UUID) {
        socket.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let ticker = try? decoder.decode(BinanceTicker.self, from: data),
                   let price = Double(ticker.c),
                   let change = Double(ticker.P) {
                    onTicker?(price, change)
                }

                stateQueue.async { [weak self] in
                    guard let self, self.connectionID == id, self.networkAvailable else { return }
                    self.lastMessageAt = Date()
                    self.retryAttempt = 0
                    self.emitStateLocked(.connected)
                    self.receive(on: socket, id: id)
                }

            case .failure:
                handleFailure(id: id)
            }
        }
    }

    private func handleFailure(id: UUID) {
        stateQueue.async { [weak self] in
            self?.handleFailureLocked(id: id)
        }
    }

    private func handleFailureLocked(id: UUID) {
        guard connectionID == id else { return }
        pingInFlight = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        guard networkAvailable else {
            emitStateLocked(.disconnected)
            return
        }

        emitStateLocked(.connecting)
        scheduleReconnectLocked()
    }

    private func scheduleReconnectLocked() {
        guard networkAvailable else { return }
        reconnectWorkItem?.cancel()
        let cappedAttempt = min(retryAttempt, 4)
        let base = min(16.0, pow(2.0, Double(cappedAttempt)))
        let delay = base + Double.random(in: 0.0...0.8)
        retryAttempt += 1
        if retryAttempt >= 4 { emitStateLocked(.disconnected) }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.networkAvailable else { return }
            self.connectLocked(resetBackoff: false)
        }
        reconnectWorkItem = work
        stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func suspendLocked() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectionID = UUID()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        retryAttempt = 0
        lastMessageAt = .distantPast
        lastPingAt = .distantPast
        pingInFlight = false
        emitStateLocked(.disconnected)
    }

    private func emitStateLocked(_ state: SocketConnectionState) {
        guard emittedState != state else { return }
        emittedState = state
        onState?(state)
    }

    /// Called by the app-level health supervisor. Active ticker traffic is its own
    /// keep-alive, so a ping is sent only after an otherwise-connected feed has been
    /// quiet for a while. This avoids two independent repeating ping timers.
    func performMaintenance(now: Date = Date()) {
        stateQueue.async { [weak self] in
            guard let self,
                  self.networkAvailable,
                  self.emittedState == .connected,
                  let socket = self.task,
                  !self.pingInFlight,
                  now.timeIntervalSince(self.lastMessageAt) >= CatoshiRuntimePolicy.socketIdlePingThreshold,
                  now.timeIntervalSince(self.lastPingAt) >= CatoshiRuntimePolicy.socketPingMinimumInterval else {
                return
            }

            let id = self.connectionID
            self.lastPingAt = now
            self.pingInFlight = true
            socket.sendPing { [weak self] error in
                guard let self else { return }
                self.stateQueue.async { [weak self] in
                    guard let self, self.connectionID == id else { return }
                    self.pingInFlight = false
                    if error != nil {
                        self.handleFailureLocked(id: id)
                    }
                }
            }
        }
    }
}

/// Thread-safe by construction: all mutable socket/reconnect state is serialized on
/// `stateQueue`; callbacks are installed once during model initialization.
final class UpbitTickerClient: @unchecked Sendable {
    var onTicker: ((String, Double) -> Void)?
    var onState: ((SocketConnectionState) -> Void)?

    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "Catoshi.UpbitSocket", qos: .utility)
    private let decoder = JSONDecoder()
    private var task: URLSessionWebSocketTask?
    private var reconnectWorkItem: DispatchWorkItem?
    private var connectionID = UUID()
    private var lastMessageAt = Date.distantPast
    private var lastPingAt = Date.distantPast
    private var pingInFlight = false
    private var retryAttempt = 0
    private var emittedState: SocketConnectionState?
    private var networkAvailable = true

    init() {
        session = URLSession(configuration: CatoshiNetworkRuntime.publicWebSocketConfiguration())
    }

    func start() {
        stateQueue.async { [weak self] in
            self?.connectLocked(resetBackoff: true)
        }
    }

    func setNetworkAvailable(_ available: Bool) {
        stateQueue.async { [weak self] in
            guard let self, self.networkAvailable != available else { return }
            self.networkAvailable = available
            if available {
                self.connectLocked(resetBackoff: true)
            } else {
                self.suspendLocked()
            }
        }
    }

    func reconnectNow() {
        stateQueue.async { [weak self] in
            guard let self, self.networkAvailable else { return }
            self.connectLocked(resetBackoff: true)
        }
    }

    func stop() {
        stateQueue.sync {
            networkAvailable = false
            suspendLocked()
        }
        session.invalidateAndCancel()
    }

    private func connectLocked(resetBackoff: Bool) {
        guard networkAvailable else {
            suspendLocked()
            return
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        let newID = UUID()
        connectionID = newID
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        if resetBackoff { retryAttempt = 0 }
        emitStateLocked(.connecting)

        guard let url = URL(string: "wss://api.upbit.com/websocket/v1") else {
            emitStateLocked(.disconnected)
            return
        }
        let socket = session.webSocketTask(with: url)
        task = socket
        lastMessageAt = Date()
        lastPingAt = .distantPast
        pingInFlight = false
        socket.resume()
        sendSubscription(on: socket, id: newID)
        receive(on: socket, id: newID)
    }

    private func sendSubscription(on socket: URLSessionWebSocketTask, id: UUID) {
        let payload = """
        [{"ticket":"Catoshi"},{"type":"ticker","codes":["KRW-BTC","KRW-USDT"]},{"format":"SIMPLE"}]
        """

        socket.send(.string(payload)) { [weak self] error in
            if error != nil { self?.handleFailure(id: id) }
        }
    }

    private func receive(on socket: URLSessionWebSocketTask, id: UUID) {
        socket.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data): handle(data: data)
                case .string(let text): handle(data: Data(text.utf8))
                @unknown default: break
                }

                stateQueue.async { [weak self] in
                    guard let self, self.connectionID == id, self.networkAvailable else { return }
                    self.lastMessageAt = Date()
                    self.retryAttempt = 0
                    self.emitStateLocked(.connected)
                    self.receive(on: socket, id: id)
                }

            case .failure:
                handleFailure(id: id)
            }
        }
    }

    private func handle(data: Data) {
        guard let item = try? decoder.decode(UpbitSimpleTicker.self, from: data),
              let price = item.tradePrice,
              let code = item.code else { return }
        onTicker?(code, price)
    }

    private func handleFailure(id: UUID) {
        stateQueue.async { [weak self] in
            self?.handleFailureLocked(id: id)
        }
    }

    private func handleFailureLocked(id: UUID) {
        guard connectionID == id else { return }
        pingInFlight = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        guard networkAvailable else {
            emitStateLocked(.disconnected)
            return
        }

        emitStateLocked(.connecting)
        scheduleReconnectLocked()
    }

    private func scheduleReconnectLocked() {
        guard networkAvailable else { return }
        reconnectWorkItem?.cancel()
        let cappedAttempt = min(retryAttempt, 4)
        let base = min(16.0, pow(2.0, Double(cappedAttempt)))
        let delay = base + Double.random(in: 0.0...0.8)
        retryAttempt += 1
        if retryAttempt >= 4 { emitStateLocked(.disconnected) }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.networkAvailable else { return }
            self.connectLocked(resetBackoff: false)
        }
        reconnectWorkItem = work
        stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func suspendLocked() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectionID = UUID()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        retryAttempt = 0
        lastMessageAt = .distantPast
        lastPingAt = .distantPast
        pingInFlight = false
        emitStateLocked(.disconnected)
    }

    private func emitStateLocked(_ state: SocketConnectionState) {
        guard emittedState != state else { return }
        emittedState = state
        onState?(state)
    }

    /// Called by the app-level health supervisor. Active ticker traffic is its own
    /// keep-alive, so a ping is sent only after an otherwise-connected feed has been
    /// quiet for a while. This avoids two independent repeating ping timers.
    func performMaintenance(now: Date = Date()) {
        stateQueue.async { [weak self] in
            guard let self,
                  self.networkAvailable,
                  self.emittedState == .connected,
                  let socket = self.task,
                  !self.pingInFlight,
                  now.timeIntervalSince(self.lastMessageAt) >= CatoshiRuntimePolicy.socketIdlePingThreshold,
                  now.timeIntervalSince(self.lastPingAt) >= CatoshiRuntimePolicy.socketPingMinimumInterval else {
                return
            }

            let id = self.connectionID
            self.lastPingAt = now
            self.pingInFlight = true
            socket.sendPing { [weak self] error in
                guard let self else { return }
                self.stateQueue.async { [weak self] in
                    guard let self, self.connectionID == id else { return }
                    self.pingInFlight = false
                    if error != nil {
                        self.handleFailureLocked(id: id)
                    }
                }
            }
        }
    }
}
