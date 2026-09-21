import Foundation
import Flynn
import Hitch

public enum WebSocketMessage {
    case text(Hitch)
    case binary(Data)
}

public protocol WebSocketDelegate {
    @discardableResult func beWebSocketOnOpen() -> Self
    @discardableResult func beWebSocketOnMessage(message: WebSocketMessage) -> Self
    @discardableResult func beWebSocketOnClose(code: UInt16, reason: Hitch?) -> Self
    @discardableResult func beWebSocketOnError(error: String) -> Self
}

public class LocalWebSocketDelegate: Actor, WebSocketDelegate {
    private let sender: Actor
    private let webSocketOnOpen: (() -> ())?
    private let webSocketOnMessage: ((WebSocketMessage) -> ())?
    private let webSocketOnClose: ((UInt16, Hitch?) -> ())?
    private let webSocketOnError: ((String) -> ())?
    
    public init(sender: Actor,
                onOpen: (() -> ())?,
                onMessage: ((WebSocketMessage) -> ())?,
                onClose: ((UInt16, Hitch?) -> ())?,
                onError: ((String) -> ())?) {
        self.sender = sender
        webSocketOnOpen = onOpen
        webSocketOnMessage = onMessage
        webSocketOnClose = onClose
        webSocketOnError = onError
    }
    
    internal func _beWebSocketOnOpen() {
        guard let localWebSocketOnOpen = webSocketOnOpen else { return }
        sender.unsafeSend { _ in
            localWebSocketOnOpen()
        }
    }
    internal func _beWebSocketOnMessage(message: WebSocketMessage) {
        guard let localWebSocketOnMessage = webSocketOnMessage else { return }
        sender.unsafeSend { _ in
            localWebSocketOnMessage(message)
        }
    }
    internal func _beWebSocketOnClose(code: UInt16, reason: Hitch?) {
        guard let localWebSocketOnClose = webSocketOnClose else { return }
        sender.unsafeSend { _ in
            localWebSocketOnClose(code, reason)
        }
    }
    internal func _beWebSocketOnError(error: String) {
        guard let localWebSocketOnError = webSocketOnError else { return }
        sender.unsafeSend { _ in
            localWebSocketOnError(error)
        }
    }
}

public class WebSocketClient: Actor {

    // MARK: - Watcher

    private class Watched {
        let client: WebSocketClient
        let socket: Socket

        init(client: WebSocketClient, socket: Socket) {
            self.client = client
            self.socket = socket
        }
    }

    private static let watchLock = NSLock()
    private static var watched: [Watched] = []
    private static var watchRunning = false

    private static func watch(client: WebSocketClient,
                              socket: Socket) {
        watchLock.lock()
        if watchRunning == false {
            watchRunning = true
            beginWatchThread()
        }
        watched.append(Watched(client: client, socket: socket))
        watchLock.unlock()
    }

    private static func beginWatchThread() {
        Thread {
            Flynn.threadSetName("Picaroon.WebSocket")

            var idleTicks = 0

            while true {
                autoreleasepool {
                    var sawActivity = false

                    watchLock.lock()
                    let localWatched = watched
                    watchLock.unlock()

                    var closed: [Watched] = []
                    for item in localWatched {
                        if item.socket.isClosed() {
                            closed.append(item)
                            continue
                        }
                        if item.socket.poll() > 0 {
                            item.client.beCheckForMoreData()
                            sawActivity = true
                        }
                    }

                    if closed.isEmpty == false {
                        watchLock.lock()
                        watched = watched.filter { item in
                            return closed.contains { $0 === item } == false
                        }
                        watchLock.unlock()

                        for item in closed {
                            item.client.beSocketDidClose()
                        }
                        sawActivity = true
                    }

                    if sawActivity {
                        idleTicks = 0
                    } else {
                        idleTicks += 1
                    }

                    Flynn.usleep(idleTicks < 200 ? 1_000 : 20_000)
                }
            }
        }.start()
    }

    private static func unwatch(client: WebSocketClient) {
        watchLock.lock()
        watched = watched.filter { $0.client !== client }
        watchLock.unlock()
    }

    // MARK: - State

    public enum State {
        case idle
        case connecting
        case open
        /// We have sent a close frame and are waiting for the peer's echo.
        case closing
        case closed
    }

    private let url: String
    private let extraHeaders: [String: String]
    private let maxMessageInBytes: Int

    private let delegate: WebSocketDelegate

    private var state: State = .idle
    private var socket: Socket?
    private var handshake: WebSocketHandshake?

    private var buffer: UnsafeMutablePointer<UInt8>
    private var bufferCapacity: Int
    private var filled = 0

    private var fragmentOpcode: WebSocketOpcode?
    private var fragments: Hitch?

    private var outbound: [Hitch] = []
    private var outboundOffset = 0

    private var didReportClose = false

    public init(url: String,
                headers: [String: String] = [:],
                maxMessageInBytes: Int = 64 * 1024 * 1024,
                delegate: WebSocketDelegate) {
        self.url = url
        self.extraHeaders = headers
        self.maxMessageInBytes = maxMessageInBytes
        self.delegate = delegate

        self.bufferCapacity = 64 * 1024
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferCapacity)

        super.init()
    }

    deinit {
        buffer.deallocate()
    }

    public func unsafeState() -> State {
        return state
    }

    // MARK: - Buffer

    @discardableResult
    private func reserve(_ needed: Int) -> Bool {
        guard needed > bufferCapacity else { return true }

        // +16 so the cap applies to the payload the caller asked to allow,
        // not to the payload minus its own frame header.
        guard needed <= maxMessageInBytes + 16 else { return false }

        var capacity = bufferCapacity
        while capacity < needed {
            capacity *= 2
        }
        capacity = min(capacity, maxMessageInBytes + 16)

        guard let grown = realloc(buffer, capacity) else { return false }

        buffer = grown.bindMemory(to: UInt8.self, capacity: capacity)
        bufferCapacity = capacity
        return true
    }

    private func consume(_ count: Int) {
        let remaining = filled - count
        if remaining > 0 {
            memmove(buffer, buffer + count, remaining)
        }
        filled = remaining
    }

    // MARK: - Connect

    internal func _beConnect() {
        guard state == .idle else {
            report(error: "connect called in state \(state)")
            return
        }

        guard let endpoint = WebSocketEndpoint(url: url) else {
            report(error: "could not parse \"\(url)\" as a ws:// url")
            return
        }

        guard let socket = Socket(blocking: true) else {
            report(error: "could not create a socket")
            return
        }

        socket.setReadTimeout(milliseconds: 50)
        socket.setWriteTimeout(milliseconds: 5_000)

        guard socket.connectTo(address: endpoint.host, port: endpoint.port) >= 0 else {
            report(error: "could not connect to \(endpoint.host):\(endpoint.port)")
            socket.close()
            return
        }

        let handshake = WebSocketHandshake()
        let request = handshake.request(endpoint: endpoint, headers: extraHeaders)

        guard socket.send(hitch: request) == request.count else {
            report(error: "could not send the upgrade request to \(endpoint.host):\(endpoint.port)")
            socket.close()
            return
        }

        self.socket = socket
        self.handshake = handshake
        self.state = .connecting

        WebSocketClient.watch(client: self, socket: socket)

        _beCheckForMoreData()
    }

    // MARK: - Read

    internal func _beCheckForMoreData() {
        guard let socket = socket else { return }
        guard state == .connecting || state == .open || state == .closing else { return }

        while socket.poll() > 0 {
            // Read in chunks rather than sizing to the frame: the header may
            // not have arrived yet, so the frame length is not always known.
            if bufferCapacity - filled < 16 * 1024 {
                guard reserve(min(bufferCapacity * 2, maxMessageInBytes + 16)) else {
                    fail(code: WebSocketCloseCode.messageTooBig,
                         error: "inbound data exceeded maxMessageInBytes (\(maxMessageInBytes))")
                    return
                }
            }

            let bytesRead = socket.recv(bytes: buffer + filled,
                                        count: bufferCapacity - filled)
            if bytesRead < 0 {
                // Socket.recv has closed the socket. Do NOT bail out here:
                // the peer's close frame and its FIN routinely arrive in the
                // same read, so whatever is already buffered still has to be
                // processed or a clean 1000 close gets reported as an
                // abnormal 1006.
                break
            }
            if bytesRead == 0 {
                break
            }

            filled += bytesRead
        }

        if state == .connecting {
            guard processHandshake() else { return }
        }

        processFrames()
    }

    private func processHandshake() -> Bool {
        guard let handshake = handshake else { return false }
        guard filled > 0 else { return false }

        switch handshake.validate(bytes: buffer, count: filled) {
        case .needMoreData:
            return false

        case .failure(let error):
            report(error: "handshake failed: \(error)")
            closeSocket()
            return false

        case .success(let consumed):
            consume(consumed)

            self.handshake = nil
            self.state = .open

            delegate.beWebSocketOnOpen()

            flushOutbound()
            return true
        }
    }

    private func processFrames() {
        while filled >= 2 {
            let result = WebSocketFrame.decodeHeader(bytes: buffer, count: filled)

            switch result {
            case .needMoreData:
                return

            case .error(let error):
                fail(code: error.closeCode, error: error.description)
                return

            case .header(let header):
                guard header.payloadCount <= maxMessageInBytes else {
                    fail(code: WebSocketCloseCode.messageTooBig,
                         error: "frame payload of \(header.payloadCount) bytes exceeds maxMessageInBytes (\(maxMessageInBytes))")
                    return
                }

                guard reserve(header.frameCount) else {
                    fail(code: WebSocketCloseCode.messageTooBig,
                         error: "could not allocate \(header.frameCount) bytes for an inbound frame")
                    return
                }

                guard filled >= header.frameCount else { return }

                let payload = buffer + header.headerCount
                let handled = handle(header: header,
                                     payload: payload,
                                     payloadCount: header.payloadCount)

                consume(header.frameCount)

                guard handled else { return }
            }
        }
    }

    private func handle(header: WebSocketFrameHeader,
                        payload: UnsafeMutablePointer<UInt8>,
                        payloadCount: Int) -> Bool {
        switch header.opcode {
        case .ping:
            // Answered even mid-fragment and even while closing, which is
            // what RFC 6455 5.5.2 requires.
            let frame = Hitch(capacity: payloadCount + 16)
            WebSocketFrame.encode(opcode: .pong,
                                  payload: payload,
                                  payloadCount: payloadCount,
                                  into: frame)
            enqueue(frame)
            return true

        case .pong:
            return true

        case .close:
            let (code, reason) = WebSocketFrame.decodeClose(payload: payload,
                                                            count: payloadCount)
            if state == .closing {
                // Our own close was echoed; the handshake is complete.
                closeSocket()
                report(close: code, reason: reason)
            } else {
                // Peer initiated. Echo the code back, then hang up.
                let frame = Hitch(capacity: 32)
                if WebSocketCloseCode.isSendable(code) {
                    WebSocketFrame.encodeClose(code: code, into: frame)
                } else {
                    WebSocketFrame.encodeClose(into: frame)
                }
                state = .closing
                enqueue(frame)

                closeSocket()
                report(close: code, reason: reason)
            }
            return false

        case .continuation:
            guard let fragments = fragments,
                  let fragmentOpcode = fragmentOpcode else {
                fail(code: WebSocketCloseCode.protocolError,
                     error: "continuation frame with no message in progress")
                return false
            }

            guard fragments.count + payloadCount <= maxMessageInBytes else {
                fail(code: WebSocketCloseCode.messageTooBig,
                     error: "reassembled message exceeds maxMessageInBytes (\(maxMessageInBytes))")
                return false
            }

            fragments.append(payload, count: payloadCount)

            if header.fin {
                deliver(opcode: fragmentOpcode, hitch: fragments)
                self.fragments = nil
                self.fragmentOpcode = nil
            }
            return true

        case .text, .binary:
            guard fragments == nil else {
                fail(code: WebSocketCloseCode.protocolError,
                     error: "new data frame arrived while a fragmented message was in progress")
                return false
            }

            if header.fin {
                // Unfragmented, which is every frame Chrome sends. Built
                // straight from the buffer with no reassembly step.
                let hitch = Hitch(bytes: payload, offset: 0, count: payloadCount)
                deliver(opcode: header.opcode, hitch: hitch)
            } else {
                let hitch = Hitch(capacity: payloadCount * 2)
                hitch.append(payload, count: payloadCount)
                fragments = hitch
                fragmentOpcode = header.opcode
            }
            return true
        }
    }

    private func deliver(opcode: WebSocketOpcode,
                         hitch: Hitch) {
        switch opcode {
        case .binary:
            delegate.beWebSocketOnMessage(message: .binary(hitch.exportAsData()))
        default:
            delegate.beWebSocketOnMessage(message: .text(hitch))
        }
    }

    // MARK: - Write

    internal func _beSend(text: Hitch) {
        guard canSend() else { return }

        let frame = Hitch(capacity: text.count + 16)
        WebSocketFrame.encode(opcode: .text, payload: text, into: frame)
        enqueue(frame)
    }

    internal func _beSend(data: Data) {
        guard canSend() else { return }

        let frame = Hitch(capacity: data.count + 16)
        WebSocketFrame.encode(opcode: .binary, payload: data, into: frame)
        enqueue(frame)
    }

    internal func _beSend(ping: Hitch?) {
        guard canSend() else { return }

        let frame = Hitch(capacity: 32)
        if let ping = ping {
            WebSocketFrame.encode(opcode: .ping, payload: ping, into: frame)
        } else {
            WebSocketFrame.encode(opcode: .ping, payload: nil, payloadCount: 0, into: frame)
        }
        enqueue(frame)
    }

    internal func _beClose(code: UInt16, reason: Hitch?) {
        guard state == .open || state == .connecting else { return }

        guard state == .open else {
            closeSocket()
            report(close: WebSocketCloseCode.goingAway, reason: nil)
            return
        }

        let frame = Hitch(capacity: 32)
        WebSocketFrame.encodeClose(code: code, reason: reason, into: frame)

        state = .closing
        enqueue(frame)
    }

    private func canSend() -> Bool {
        switch state {
        case .open, .connecting:
            return true
        default:
            report(error: "cannot send in state \(state)")
            return false
        }
    }

    private func enqueue(_ frame: Hitch) {
        outbound.append(frame)
        flushOutbound()
    }

    private func flushOutbound() {
        guard state == .open || state == .closing else { return }
        guard let socket = socket else { return }

        while let frame = outbound.first {
            guard let raw = frame.raw() else {
                outbound.removeFirst()
                outboundOffset = 0
                continue
            }

            let remaining = frame.count - outboundOffset
            guard remaining > 0 else {
                outbound.removeFirst()
                outboundOffset = 0
                continue
            }

            let sent = socket.send(bytes: raw + outboundOffset, count: remaining)
            if sent < 0 {
                // Socket.send closes on error; the watcher reports it.
                return
            }

            outboundOffset += sent

            if outboundOffset >= frame.count {
                outbound.removeFirst()
                outboundOffset = 0
            } else {
                // Short write. The rest goes out on the next watcher tick
                // rather than spinning here holding a scheduler thread.
                return
            }
        }

        if state == .closing && outbound.isEmpty {
            // Our close frame is on the wire. Wait for the echo rather than
            // hanging up, so the peer can finish reading what we sent.
        }
    }

    // MARK: - Teardown

    /// Called by the watcher once the socket has closed, whoever closed it.
    internal func _beSocketDidClose() {
        WebSocketClient.unwatch(client: self)

        // A socket that went away without a close handshake is 1006, which is
        // local-only and never appears on the wire.
        report(close: 1006, reason: nil)
        state = .closed
    }

    private func fail(code: UInt16, error: String) {
        report(error: error)

        if state == .open {
            let frame = Hitch(capacity: 32)
            WebSocketFrame.encodeClose(code: code, into: frame)
            state = .closing
            enqueue(frame)
        }

        closeSocket()
        report(close: code, reason: nil)
    }

    private func closeSocket() {
        state = .closed
        socket?.close()
        WebSocketClient.unwatch(client: self)
    }

    private func report(error: String) {
        delegate.beWebSocketOnError(error: error)
    }

    private func report(close code: UInt16, reason: Hitch?) {
        guard didReportClose == false else { return }
        didReportClose = true

        delegate.beWebSocketOnClose(code: code,
                                    reason: reason)
    }
}
