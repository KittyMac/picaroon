import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#else
#error("Unknown platform")
#endif

fileprivate struct StringError: LocalizedError {
    let errorDescription: String?
    init(_ description: String) { self.errorDescription = description }
}

/// The only two things HTTPTaskManager needs from a task, so a CurlTask and a
/// URLSessionDataTask are interchangeable at the call site.
internal protocol PicaroonTask: AnyObject {
    func resume()
    func cancel()
}

extension URLSessionDataTask: PicaroonTask { }

fileprivate struct DataTask {
    let task: PicaroonTask
    let proxy: String?
}

/// Lets the completion closure identify the task it belongs to, which does not exist
/// yet when the closure is built. PicaroonTask has no `response`, so activeTasks can
/// no longer be matched the way it was.
fileprivate final class DataTaskBox {
    var task: PicaroonTask?
}

internal class HTTPTaskManager: Actor {
    internal static let shared = HTTPTaskManager()
    private override init() {
        super.init()
        
        unsafePriority = 9999
        unsafeMessageBatchSize = 9999
    }
    
    #if os(Windows)
    private let maxConcurrentTasks = 16
    #elseif os(Linux)
    private let maxConcurrentTasks = 512
    #elseif os(Android)
    private let maxConcurrentTasks = 8
    #else
    private let maxConcurrentTasks = min(max(Flynn.cores * 4, 4), 64)
    #endif
    
    private var waitingTasks: [DataTask] = []
    private var activeTasks: [DataTask] = []
    
    private var didWarnAbountProxy = false
    
    private func checkForMoreTasks() {
        guard waitingTasks.isEmpty == false else { return }
        guard activeTasks.count < maxConcurrentTasks else { return }
        
        let task = waitingTasks.removeFirst()
        activeTasks.append(task)
        
        #if os(Windows)
        task.task.resume()
        #else
        // This is super hacky, but here it goes.
        // We can get per-session-task proxy by setting an environment
        // variable which libcurl uses to know that this requst should
        // be proxied. This var is read in the future on a dispatch
        // queue which URLSessionTask uses internally. We need to
        // set the var, tell the task to resume, and then call
        // some other method on the task which we know sync's to
        // the work queue. Once we return from that, we can clear
        // the proxy var.
        // Note: this is also only safe in the context of Picaroon and HttpSessionManager
        // where all URLSessionTasks are funnelled through the HTTPTaskManager actor
        // (thus none of these will execute concurrently)
        // Note: per session proxies are only supported on linux
        if let proxy = task.proxy,
           let urlTask = task.task as? URLSessionDataTask {
#if !os(Linux)
            if didWarnAbountProxy == false {
                didWarnAbountProxy = true
                print("warning: URLSessionDataTasks do not support proxy on this platform")
            }
#endif
            setenv("all_proxy", proxy, 1)
            urlTask.resume()
            urlTask.priority = URLSessionTask.defaultPriority
            unsetenv("all_proxy")
        } else {
            // CurlTask carries its proxy on the handle (CURLOPT_PROXY), so it needs
            // none of the above.
            task.task.resume()
        }
        #endif
    }
    
    internal func _beResume(session: URLSession,
                            request _request: URLRequest,
                            proxy: String?,
                            timeoutRetry: Int,
                            retryAnyError: Bool,
                            _ returnCallback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        var request = _request
        #if os(Android) || os(Linux)
        // On android specifically, the first time we make a network call it always time outs
        // To help work around this, we give the first network call a small timeout value
        // Note: this works around a corelibs URLSession stall that CurlTransport avoids
        // entirely, so it is skipped when the curl transport is active.
        if CurlTransport.enabled == false,
           session.sessionDescription == sessionState_Inited {
            request.timeoutInterval = 2
        }
        #endif
        if session.sessionDescription == sessionState_Inited {
            session.sessionDescription = sessionState_Normal
        }

        
        guard session.sessionDescription == sessionState_Normal else {
            return returnCallback(nil, nil, StringError("invalid session state - \(session.sessionDescription ?? "unknown")"))
        }

        let taskBox = DataTaskBox()
        let completionHandler: (Data?, URLResponse?, Error?) -> () = { data, response, error in
#if os(Linux) || os(Android)
            _ = signal(SIGPIPE, SIG_IGN)
#endif
            
            self.unsafeSend { _ in
                if let boxedTask = taskBox.task {
                    self.activeTasks.removeAll { $0.task === boxedTask }
                }
                
                var shouldBeRetried: String? = nil
                var shouldBeRecycled: String? = nil
                                   
                // Allow specific error to be retried
                if let error = error as? URLError,
                   (error.code == .timedOut ||
                    error.code == .networkConnectionLost ||
                    error.errorCode == 104 ||
                    error.errorCode == -1001 ||
                    error.errorCode == -1003 ||
                    error.errorCode == -1005) {
                    shouldBeRetried = "timeout detected \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
                    if error.errorCode == -1001 {
                        shouldBeRecycled = "error -1001 detected - recycle session"
                    }
                }
                
                // If we timeout out, go ahead and retry it.
                #if !os(Windows)
                if let error = error as? POSIXError,
                   (error.code == .ENOSPC ||
                    error.code == .ECONNRESET ||
                    error.errorCode == 54 ||
                    error.errorCode == 104 ||
                    error.errorCode == -1001 ||
                    error.errorCode == -1003 ||
                    error.errorCode == -1005) {
                    shouldBeRetried = "no space detected \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
                    if error.errorCode == -1001 {
                        shouldBeRecycled = "error -1001 detected - recycle session"
                    }
                }
                #else
                if let error = error as? POSIXError,
                   (error.code == .ENOSPC ||
                    error.errorCode == 104 ||
                    error.errorCode == 104 ||
                    error.errorCode == -1001 ||
                    error.errorCode == -1003 ||
                    error.errorCode == -1005) {
                    shouldBeRetried = "no space detected \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
                    if error.errorCode == -1001 {
                        shouldBeRecycled = "error -1001 detected - recycle session"
                    }
                }
                #endif
                
                if error.debugDescription.contains("hostname could not be found") {
                    shouldBeRetried = nil
                }
                
                if retryAnyError {
                    // Any transport error
                    if let error = error {
                        shouldBeRetried = "retry any error: \(error)"
                    }
                    // Any non-success HTTP error
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                        shouldBeRetried = "retry any error: http \(httpResponse.statusCode)"
                    }
                }
                
                // Retries on specific error string content
                if let errorString = error?.localizedDescription,
                   timeoutRetry > 0 {
                    let retryErrorStrings = [
                        "Transferred a partial file"
                    ]
                    
                    for retryErrorString in retryErrorStrings where errorString.contains(retryErrorString) {
                        shouldBeRetried = "\(retryErrorString) \(timeoutRetry), retrying \(request.url?.absoluteString ?? "unknown url")..."
                    }
                }
                
                // If we timeout out, go ahead and retry it.
                if let shouldBeRetried = shouldBeRetried,
                   timeoutRetry > 0 {
                    print(shouldBeRetried)
                    
                    var newRequest = request
                    
                    #if os(Android) || os(Linux)
                    if request.timeoutInterval == 2 {
                        newRequest.timeoutInterval = 60
                        shouldBeRecycled = nil
                    }
                    #endif
                    
                    if let shouldBeRecycled = shouldBeRecycled {
                        // flag the original session as needing to be recycled.
                        session.sessionDescription = sessionState_Recycle
                        
                        // create a new, temporary session for our retry attempt
                        let tempSession = URLSession(configuration: session.configuration,
                                                     delegate: nil,
                                                     delegateQueue: nil)
                        tempSession.sessionDescription = sessionState_Inited
                        
                        Flynn.Timer(timeInterval: 1.0, immediate: false, repeats: false, self) { [weak self] timer in
                            guard let self = self else { return returnCallback(nil, nil, nil) }
                            self.beResume(session: tempSession,
                                          request: newRequest,
                                          proxy: proxy,
                                          timeoutRetry: timeoutRetry - 1,
                                          retryAnyError: retryAnyError,
                                          self) { data, response, error in
                                tempSession.finishTasksAndInvalidate()
                                tempSession.sessionDescription = sessionState_Invalidated
                                returnCallback(data, response, error)
                            }
                        }
                        return
                    }
                    
                    Flynn.Timer(timeInterval: 1.0, immediate: false, repeats: false, self) { [weak self] timer in
                        guard let self = self else { return returnCallback(nil, nil, nil) }
                        self.beResume(session: session,
                                      request: newRequest,
                                      proxy: proxy,
                                      timeoutRetry: timeoutRetry - 1,
                                      retryAnyError: retryAnyError,
                                      self,
                                      returnCallback)
                    }
                    return
                }
                
                self.checkForMoreTasks()
                returnCallback(data, response, error)
            }
        }
        
        let task: PicaroonTask
        #if os(Linux) || os(Android)
        if CurlTransport.enabled {
            task = CurlTransport.makeTask(session: session,
                                          request: request,
                                          proxy: proxy,
                                          completionHandler)
        } else {
            task = session.dataTask(with: request, completionHandler: completionHandler)
        }
        #else
        task = session.dataTask(with: request, completionHandler: completionHandler)
        #endif
        taskBox.task = task
        
        waitingTasks.append(DataTask(task: task,
                                     proxy: proxy))
        self.checkForMoreTasks()
    }
}
