import Foundation
import Flynn
import Hitch
import Spanker
import Sextant

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// NOTE: all windows created are ephemeral and separate;
// each pair should be created and destroyed together
// to avoid leaking profiles. sessionUUID is required
// to route target level commands
public struct CDPWindow {
    public let profileUUID: String
    public let windowUUID: String
    public let sessionUUID: String
}

private struct PendingResult {
    let method: Hitch
    let resultPath: Hitch?
    let callback: (Hitch?, Hitch?, String?) -> ()
}

public class CDPBrowser: IOActor, WebSocketDelegate {

    private let host: String
    private let port: Int
    private let disposeOnDetach: Bool
    
    private var client: WebSocketClient? = nil
    
    private var isConnected = false
    private var nextId = 1
    private var pending: [Int: PendingResult] = [:]
    
    private var activeWindows: [String: CDPWindow] = [:]

    public init(host: String = "127.0.0.1",
                port: Int = 9222,
                disposeOnDetach: Bool = true) {
        self.host = host
        self.port = port
        self.disposeOnDetach = disposeOnDetach

        super.init()
    }

    // MARK: - Connect
    
    internal func _beConnect(_ returnCallback: @escaping (String?) -> ()) {
        guard client == nil else {
            returnCallback("connection in progress")
            return
        }
        
        // first see if this chrome responds to the /json/version API
        let versionUrl = "http://\(host):\(port)/json/version"
        let (data, _, _) = HTTPSession.oneshot.unsafeSynchronousRequest(url: versionUrl,
                                                                        httpMethod: "GET",
                                                                        params: [:],
                                                                        headers: [:],
                                                                        cookies: nil,
                                                                        timeoutRetry: 3,
                                                                        proxy: nil,
                                                                        body: nil)
        var browserUrl: String? = nil
        
        if let data = data,
           let root = Spanker.parse(halfhitch: HalfHitch(data: data)),
           let debuggerUrl: Hitch = root["webSocketDebuggerUrl"] {
            browserUrl = debuggerUrl.toString()
        } else {
            
            // failed to get the url from the json/version API; we can fallback to local files
            // if the target chrome is running locally
            guard host == "127.0.0.1" else {
                returnCallback("failed to discover browser url to \(host):\(port)")
                return
            }
            
            #if os(macOS)
            let devToolsPath = "\(NSHomeDirectory())/Library/Application Support/Google/Chrome/DevToolsActivePort"
            #elseif os(Linux)
            let devToolsPath = "\(NSHomeDirectory())/.config/google-chrome/DevToolsActivePort"
            #else
            let devToolsPath = ""
            returnCallback("chrome discovery is unavailable on this platform")
            return
            #endif
            guard let contents = try? String(contentsOfFile: devToolsPath, encoding: .utf8) else {
                returnCallback("chrome discovery failed: \(devToolsPath) does not exist")
                return
            }
            
            let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
            guard lines.count >= 2,
                  let port = Int(lines[0].trimmingCharacters(in: .whitespaces)) else {
                returnCallback("chrome discovery failed to parse \(devToolsPath)")
                return
            }
            
            let browserPath = lines[1].trimmingCharacters(in: .whitespaces)
            browserUrl = "ws://\(host):\(port)\(browserPath)"
        }
        
        guard let browserUrl = browserUrl else {
            returnCallback("failed to discover chrome browser url")
            return
        }
        
        
        client = WebSocketClient(url: browserUrl,
                                 delegate: self)

        client?.beConnect()
        
        returnCallback(nil)
    }
    
    internal func _beWebSocketOnOpen() {
        isConnected = true
    }
    
    internal func _beWebSocketOnMessage(message: WebSocketMessage) {
        // The root must outlive the dispatch below: sub-elements are handed to
        // callbacks that may hold them.
        #if DEBUG
        print("message: \(message)")
        #endif
        
        guard case .text(let resultJson) = message else { return }

        guard let root = Spanker.parse(halfhitch: resultJson.halfhitch()) else {
            _beWebSocketOnError(error: "could not parse CDP message as JSON")
            return
        }
        
        if let id: Int = root["id"] {
            guard let pendingResult = pending.removeValue(forKey: id) else {
                // A response to a command we are no longer tracking. Not fatal;
                // it happens if the caller gave up, and dropping it silently
                // would hide a correlation bug.
                _beWebSocketOnError(error: "received a response for unknown command id \(id)")
                return
            }
            
            // TODO: update for correct error handling
            if let error = root["error"] as JsonElement? {
                let code: Int = error["code"] ?? 0
                let text: Hitch = error["message"] ?? "unknown error"
                pendingResult.callback(nil, nil, "CDP error \(code): \(text.toString())")
                return
            }
            
            // TODO: extract the JS result
            if let resultPath = pendingResult.resultPath,
               let result = root.query(element: resultPath) {
                if let hitchValue = result.hitchValue {
                    return pendingResult.callback(hitchValue, resultJson, nil)
                } else {
                    return pendingResult.callback(result.toHitch(), resultJson, nil)
                }
            }
            return pendingResult.callback(nil, resultJson, nil)
        }
        
        // NOTE: events which are shared from the chrome client which are not a
        // direct response to a command we sent
        if let method: Hitch = root["method"] {
            print("unknown: \(method)")
            //onEvent?(method, root["params"] as JsonElement?)
            return
        }
        
        _beWebSocketOnError(error: "CDP message had neither an id nor a method")
    }
    
    internal func _beWebSocketOnClose(code: UInt16, reason: Hitch?) {
        handleClose(code: code)
    }
    
    internal func _beWebSocketOnError(error: String) {
        print("_beWebSocketOnError: \(error)")
        // handleClose()
    }
    
    private func handleClose(code: UInt16) {
        // Fail everything still outstanding. Without this a caller waiting on
        // a command that will now never be answered hangs forever, which on a
        // browser that crashed is exactly when you least want to be guessing.
        let outstanding = pending
        pending.removeAll()
        
        for (_, pendingResult) in outstanding {
            pendingResult.callback(nil, nil, "connection closed (\(code)) before the command completed")
        }
        
        isConnected = false
        nextId = 1
        activeWindows = [:]
        client = nil
    }
    
    internal func _beClose() {
        client?.beClose(code: WebSocketCloseCode.normal,
                        reason: nil)
        client = nil
    }

    internal func _beSend(method: Hitch,
                          sessionId: String?,
                          params: JsonElement?,
                          resultPath: Hitch?,
                          _ returnCallback: @escaping (Hitch?, Hitch?, String?) -> ()) {
        guard let client = client else { return returnCallback(nil, nil, "not connected") }
        
        let id = nextId
        nextId += 1
        
        pending[id] = PendingResult(method: method,
                                    resultPath: resultPath,
                                    callback: returnCallback)
        
        let requestElement = ^[:]
        requestElement.set(key: "id", value: id)
        requestElement.set(key: "method", value: method)
        requestElement.set(key: "params", value: params)
        
        if let sessionId = sessionId {
            requestElement.set(key: "sessionId", value: sessionId)
        }
        
        let request = requestElement.toHitch()
        print(request)
        client.beSend(text: request)
    }
    
    // MARK: - Windows

    internal func _beNewWindow(_ returnCallback: @escaping (String?, String?) -> ()) {
        beSend(method: "Target.createBrowserContext",
               sessionId: nil,
               params: ^[
                "disposeOnDetach": disposeOnDetach
               ],
               resultPath: "$.result.browserContextId",
               self) { profileUUID, resultJson, error in
            if let error = error {
                returnCallback(nil, "Target.createBrowserContext failed: \(error)")
                return
            }
            guard let profileUUID = profileUUID?.toString() else {
                returnCallback(nil, "Target.createBrowserContext returned no browserContextId")
                return
            }
            
            self.beSend(method: "Target.createTarget",
                        sessionId: nil,
                        params: ^[
                            "url": "about:blank",
                            "browserContextId": profileUUID,
                            "newWindow": true
                        ],
                        resultPath: "$.result.targetId",
                        self) { windowUUID, resultJson, error in
                if let error = error {
                    returnCallback(nil, "Target.createTarget failed: \(error)")
                    return
                }
                guard let windowUUID = windowUUID?.toString() else {
                    returnCallback(nil, "Target.createTarget returned no targetId")
                    return
                }
                
                self.beSend(method: "Target.attachToTarget",
                            sessionId: nil,
                            params: ^[
                                "targetId": windowUUID,
                                "flatten": true
                            ],
                            resultPath: "$.result.sessionId",
                            self) { sessionUUID, resultJson, error in
                    if let error = error {
                        returnCallback(nil, "Target.attachToTarget failed: \(error)")
                        return
                    }
                    guard let sessionUUID = sessionUUID?.toString() else {
                        returnCallback(nil, "Target.attachToTarget returned no targetId")
                        return
                    }
                    
                    self.activeWindows[windowUUID] = CDPWindow(profileUUID: profileUUID,
                                                               windowUUID: windowUUID,
                                                               sessionUUID: sessionUUID)
                    
                    returnCallback(windowUUID, nil)
                }
            }
        }
    }
    
    internal func _beCloseWindow(webviewUUID: String,
                                 _ returnCallback: @escaping (String?) -> ()) {
        guard let activeWindow = activeWindows[webviewUUID] else {
            return returnCallback("\(webviewUUID) does not exist")
        }
        activeWindows[webviewUUID] = nil

        beSend(method: "Target.closeTarget",
               sessionId: nil,
               params: ^[
                "targetId": activeWindow.windowUUID
               ],
               resultPath: nil,
               self) { _, _, error in
            self.beSend(method: "Target.disposeBrowserContext",
                        sessionId: nil,
                        params: ^[
                            "browserContextId": activeWindow.profileUUID
                        ],
                        resultPath: nil,
                        self) { _, _, error in
                returnCallback(error)
            }
        }
    }
    
    internal func _beLoadURL(webviewUUID: String,
                             url: String,
                             referrer: String?,
                             _ returnCallback: @escaping (String?) -> ()) {
        guard let activeWindow = activeWindows[webviewUUID] else {
            return returnCallback("\(webviewUUID) does not exist")
        }
        
        let params = ^[
            "url": url,
        ]
        if let referrer = referrer {
            params.set(key: "referrer", value: referrer)
        }

        beSend(method: "Page.navigate",
               sessionId: activeWindow.sessionUUID,
               params: params,
               resultPath: nil,
               self) { _, _, error in
            returnCallback(error)
        }
    }
    
    internal func _beEvaluate(webviewUUID: String,
                              script: String,
                              _ returnCallback: @escaping (Hitch?, String?) -> ()) {
        guard let activeWindow = activeWindows[webviewUUID] else {
            return returnCallback(nil, "\(webviewUUID) does not exist")
        }

        beSend(method: "Runtime.evaluate",
               sessionId: activeWindow.sessionUUID,
               params: ^[
                "expression": script,
                "returnByValue": true
               ],
               resultPath: "$.result.result.value",
               self) { result, resultJson, error in
            returnCallback(result, error)
        }
    }
}
