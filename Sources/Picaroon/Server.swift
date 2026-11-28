import Foundation
import Flynn
import Hitch

#if os(Linux) || os(Android) || os(Windows)
public func autoreleasepool(_ block: @escaping () -> ()) {
    block()
}
#endif

public typealias StaticStorageHandler = (Connection, ServerConfig, HttpRequest) -> HttpResponse?

/// Three different mechanisms for allowing session persistance, in order from most complicated to
/// least complicated.
///
/// window:     a two UUID system which uses one http-only cookie UUID and a separate
///         Session-Id http header. The cookie uuid "painlessly" persists a session
///         to the browser level, however is the same across all windows. Session-Id is
///         expected to be received, stored in session storage, and sent back with future requests.
///         This allows granularity at the window level. The combination of the two then provides
///         the full, unique session UUID.
///
/// browser:    same as window above but it only uses the http-only cookie UUID.
///
/// api:            same as window above, but only uses Session-Id passes along in the http headers.
///
public enum UserSessionPer: Int, Codable {
    case window = 0
    case browser = 1
    case api = 2
}

/// SameSite attribute for the session cookie. (None is deliberately not offered; nothing in Picaroon's
/// session model needs the session cookie on cross-site subrequests.)
public enum CookieSameSite: String, Codable {
    /// Sent on same-site requests and on top-level cross-site GET navigations (ie returning from a
    /// third party login), withheld from cross-site POSTs and subresources. Recommended.
    case lax = "Lax"
    /// Never sent cross-site, including the redirect back from a third party login; such returns
    /// must then always go through a reassociation token.
    case strict = "Strict"
}

public struct ServerConfig: Codable {
    public let address: Hitch
    public let port: Int

    public let basePath: Hitch
    
    public let clientTimeout: TimeInterval
    public let serverTimeout: TimeInterval
    
    /// Longest a single send to a client may block before the connection is dropped. 0 disables it.
    public let writeTimeout: TimeInterval
    
    public let maxRequestInBytes: Int
    
    /// Most connections open at once; beyond it new connections get a 503 and are closed.
    /// 0 (the default) picks a limit just under the process's file descriptor limit, leaving
    /// headroom for files, outbound requests and logging. Negative means unlimited.
    public let maxConnections: Int
    public let connectionMaxBackoff: Double

    public let sessionPer: UserSessionPer
    public let sessionActivityTimeout: TimeInterval
    public let maximumSessions: Int
    
    /// When true (the default) the session cookie is sent with Secure and the __Host- name prefix, which
    /// stops it being set or overwritten over plain http or from a sibling subdomain. Requires the browser
    /// to reach you over https (TLS terminated here or at a proxy). Set false only for plain http
    /// development; browsers will otherwise silently drop the cookie and every request gets a new session.
    public let cookieSecure: Bool
    public let cookieSameSite: CookieSameSite
    
    public let debug: Bool

    /// The name the session cookie is sent and read under.
    public var sessionCookieName: Hitch {
        guard cookieSecure else { return Picaroon.userSessionCookie }
        let name = Hitch(capacity: 7 + Picaroon.userSessionCookie.count)
        name.append(hitchHostCookiePrefix)
        name.append(Picaroon.userSessionCookie)
        return name
    }

    public init(address: String,
                port: Int,
                basePath: String = "/",
                sessionPer: UserSessionPer = .window,
                sessionActivityTimeout: TimeInterval = 60 * 60,
                maximumSessions: Int = 1_000_000,
                clientTimeout: TimeInterval = 5.0,
                serverTimeout: TimeInterval = 30.0,
                writeTimeout: TimeInterval = 10.0,
                maxRequestInBytes: Int = 1024 * 1024 * 8,
                maxConnections: Int = 0,
                connectionMaxBackoff: Double = 0.5,
                cookieSecure: Bool = true,
                cookieSameSite: CookieSameSite = .lax,
                debug: Bool = false) {
        self.address = Hitch(string: address)
        self.port = port
        self.sessionPer = sessionPer
        self.sessionActivityTimeout = sessionActivityTimeout
        self.maximumSessions = maximumSessions
        self.clientTimeout = clientTimeout
        self.serverTimeout = serverTimeout
        self.writeTimeout = writeTimeout
        self.maxRequestInBytes = maxRequestInBytes
        self.maxConnections = maxConnections
        self.connectionMaxBackoff = connectionMaxBackoff
        self.cookieSecure = cookieSecure
        self.cookieSameSite = cookieSameSite
        self.debug = debug
        self.basePath = Hitch(string: basePath)
        
        if self.basePath.ends(with: "/") {
            self.basePath.count = self.basePath.count - 1
        }
    }

    private enum CodingKeys: String, CodingKey {
        case address, port, basePath, clientTimeout, serverTimeout, maxRequestInBytes, connectionMaxBackoff
        case sessionPer, sessionActivityTimeout, maximumSessions, cookieSecure, cookieSameSite, debug
        case writeTimeout, maxConnections
    }

    // Explicit so that configs serialized before the cookie settings existed still decode (to the defaults)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(Hitch.self, forKey: .address)
        port = try container.decode(Int.self, forKey: .port)
        basePath = try container.decode(Hitch.self, forKey: .basePath)
        clientTimeout = try container.decode(TimeInterval.self, forKey: .clientTimeout)
        serverTimeout = try container.decode(TimeInterval.self, forKey: .serverTimeout)
        writeTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .writeTimeout) ?? 10.0
        maxRequestInBytes = try container.decode(Int.self, forKey: .maxRequestInBytes)
        maxConnections = try container.decodeIfPresent(Int.self, forKey: .maxConnections) ?? 0
        connectionMaxBackoff = try container.decode(Double.self, forKey: .connectionMaxBackoff)
        sessionPer = try container.decode(UserSessionPer.self, forKey: .sessionPer)
        sessionActivityTimeout = try container.decode(TimeInterval.self, forKey: .sessionActivityTimeout)
        maximumSessions = try container.decode(Int.self, forKey: .maximumSessions)
        cookieSecure = try container.decodeIfPresent(Bool.self, forKey: .cookieSecure) ?? true
        cookieSameSite = try container.decodeIfPresent(CookieSameSite.self, forKey: .cookieSameSite) ?? .lax
        debug = try container.decode(Bool.self, forKey: .debug)
    }
}

private let hitchHostCookiePrefix: Hitch = "__Host-"

extension ServerConfig {
    /// The connection limit actually enforced, resolving maxConnections' automatic and unlimited
    /// settings. 0 means unlimited.
    public var effectiveMaxConnections: Int {
        if maxConnections > 0 { return maxConnections }
        if maxConnections < 0 { return 0 }
        
        guard let descriptorLimit = ServerConfig.softDescriptorLimit() else { return 0 }
        // Leave room for everything else the process opens. With a tiny limit, still allow a few.
        return max(32, descriptorLimit - 128)
    }
    
    private static func softDescriptorLimit() -> Int? {
        #if os(Linux) || canImport(Darwin)
        var limit = rlimit()
        #if os(Linux)
        let result = getrlimit(__rlimit_resource_t(RLIMIT_NOFILE.rawValue), &limit)
        #else
        let result = getrlimit(RLIMIT_NOFILE, &limit)
        #endif
        // RLIM_INFINITY clamps to Int.max, which is effectively unlimited
        guard result == 0 else { return nil }
        return Int(clamping: limit.rlim_cur)
        #else
        return nil
        #endif
    }
}

public class Server<T: UserSession> {
    // A server which listens on an address and a port

    public let config: ServerConfig

    private var listening = false

    private var userSessionManager: UserSessionManager<T>
    public var staticStorageHandler: StaticStorageHandler?

    public init(config: ServerConfig,
                staticStorageHandler: StaticStorageHandler? = nil) {
        self.config = config
        self.staticStorageHandler = staticStorageHandler
        self.userSessionManager = UserSessionManager<T>(config: config)
    }

    @discardableResult
    private func loop() -> Bool {
        guard let serverSocket = Socket(blocking: true) else { return false }
        if config.debug {
            fputs("listen on \(config.address.description) \(config.port)\n", stderr)
        }
        guard serverSocket.listen(address: config.address.description,
                                  port: config.port) == 0 else {
            Flynn.syslog("Picaroon", "failed to listen on \(config.address.description):\(config.port), errno \(errno)")
            return false
        }

        // accept() fails immediately and repeatedly when the process is out of file descriptors
        // (EMFILE/ENFILE): the pending connection stays queued, so retrying at once spins a core at
        // 100% while the listen backlog fills and new clients time out. Back off exponentially
        // (1ms up to 100ms) while it keeps failing, and log at most every 10 seconds.
        var consecutiveAcceptFailures: UInt64 = 0
        var lastAcceptFailureLog: TimeInterval = 0
        
        let connectionLimit = config.effectiveMaxConnections
        var lastConnectionLimitLog: TimeInterval = 0

        repeat {
            autoreleasepool {
                var clientAddress = ""
                if self.config.debug {
                    fputs("accept on \(self.config.address.description) \(self.config.port)\n", stderr)
                }
                if let newSocket = serverSocket.accept(blocking: true, clientAddress: &clientAddress) {
                    if self.config.debug {
                        fputs("read on \(self.config.address.description) \(self.config.port)\n", stderr)
                    }
                    consecutiveAcceptFailures = 0
                    
                    // Over the connection limit: answer 503 and close, rather than taking on a
                    // connection we may not have the descriptors or memory to serve.
                    if connectionLimit > 0 && ConnectionManager_ActiveCount() >= connectionLimit {
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastConnectionLimitLog > 10 {
                            lastConnectionLimitLog = now
                            Flynn.syslog("Picaroon", "connection limit of \(connectionLimit) reached on port \(self.config.port); rejecting new connections")
                        }
                        newSocket.setWriteTimeout(milliseconds: 1000)
                        HttpStaticResponse.serviceUnavailable.send(config: self.config, socket: newSocket, userSession: nil)
                        newSocket.close()
                        return
                    }
                    
                    ConnectionManager_OpenConnection(socket: newSocket,
                                                     clientAddress: clientAddress,
                                                     config: self.config,
                                                     staticStorageHandler: self.staticStorageHandler,
                                                     userSessionManager: self.userSessionManager)
                } else {
                    consecutiveAcceptFailures += 1
                    
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastAcceptFailureLog > 10 {
                        lastAcceptFailureLog = now
                        Flynn.syslog("Picaroon", "accept failed on port \(self.config.port), errno \(serverSocket.lastAcceptError) (\(consecutiveAcceptFailures) consecutive)")
                    }
                    
                    // Flynn.usleep takes microseconds
                    let backoff: UInt64 = min(100_000, 1_000 << min(consecutiveAcceptFailures - 1, 7))
                    Flynn.usleep(backoff)
                }
            }
        } while self.listening
        return true
    }

    @discardableResult
    public func run() -> Bool {
        // run the server synchronously
        guard !listening else { return false }
        listening = true
        return loop()
    }

    public func listen() {
        // run the server asynchronously
        guard !listening else { return }

        listening = true
        Thread {
            Flynn.threadSetName("Picaroon.Server")
            self.loop()
        }.start()
    }

    public func stop() {
        listening = false
    }

    public func numberOfUserSessions() -> Int {
        return userSessionManager.numberOfUserSessions()
    }
}
