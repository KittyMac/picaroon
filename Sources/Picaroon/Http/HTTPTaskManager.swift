import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

fileprivate struct DataTask: Equatable {
    let task: URLSessionDataTask
    let proxy: String?
}

internal class HTTPTaskManager: Actor {
    internal static let shared = HTTPTaskManager()
    private override init() { }
    
    private let maxConcurrentTasks = 96
    
    private var waitingTasks: [DataTask] = []
    private var activeTasks: [DataTask] = []
    
    private var didWarnAbountProxy = false
    
    private func checkForMoreTasks() {
        guard waitingTasks.isEmpty == false else { return }
        guard activeTasks.count < maxConcurrentTasks else { return }
        
        let task = waitingTasks.removeFirst()
        activeTasks.append(task)
        
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
        if let proxy = task.proxy {
            #if !os(Linux)
            if didWarnAbountProxy == false {
                didWarnAbountProxy = true
                print("warning: URLSessionDataTasks do not support proxy on this platform")
            }
            #endif
            setenv("all_proxy", proxy, 1)
            task.task.resume()
            task.task.priority = URLSessionTask.defaultPriority
            unsetenv("all_proxy")
        } else {
            task.task.resume()
        }
    }
        
    internal func _beResume(session: URLSession,
                            request: URLRequest,
                            proxy: String?,
                            timeoutRetry: Int,
                            _ returnCallback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        let task = session.dataTask(with: request) { data, response, error in
            #if os(Linux) || os(Android)
            _ = signal(SIGPIPE, SIG_IGN)
            #endif
            
            self.unsafeSend { _ in
                for task in self.activeTasks where task.task.response == response {
                    self.activeTasks.removeOne(task)
                    break
                }
                self.checkForMoreTasks()
                
                // If we timeout out, go ahead and retry it.
                if let error = error as? URLError,
                   error.code == .timedOut && timeoutRetry > 0 {
                    #if DEBUG
                    print("timeout detected, retrying \(timeoutRetry)...")
                    #endif
                    self._beResume(session: session,
                                   request: request,
                                   proxy: proxy,
                                   timeoutRetry: timeoutRetry - 1,
                                   returnCallback)
                    return
                }
                
                // If we timeout out, go ahead and retry it.
                if let error = error as? POSIXError,
                   error.code == .ENOSPC && timeoutRetry > 0 {
                    #if DEBUG
                    print("no space detected, retrying \(timeoutRetry)...")
                    #endif
                    session.flush {
                        self.unsafeSend { _ in
                            self._beResume(session: session,
                                           request: request,
                                           proxy: proxy,
                                           timeoutRetry: timeoutRetry - 1,
                                           returnCallback)
                        }
                    }
                    return
                }
                
                returnCallback(data, response, error)
            }
        }
        waitingTasks.append(DataTask(task: task,
                                     proxy: proxy))
        self.checkForMoreTasks()
    }
}
