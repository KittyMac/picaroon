import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal class HTTPTaskManager: Actor {
    internal static let shared = HTTPTaskManager()
    private override init() { }
    
    private let maxConcurrentTasks = 256
    
    private var waitingTasks: [URLSessionDataTask] = []
    private var activeTasks: [URLSessionDataTask] = []
    
    private func checkForMoreTasks() {
        guard waitingTasks.isEmpty == false else { return }
        guard activeTasks.count < maxConcurrentTasks else { return }
        
        let task = waitingTasks.removeFirst()
        activeTasks.append(task)
        task.resume()
    }
        
    internal func _beResume(session: URLSession,
                            request: URLRequest,
                            timeoutRetry: Int,
                            _ returnCallback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        let task = session.dataTask(with: request) { data, response, error in
            #if os(Linux)
            _ = signal(SIGPIPE, SIG_IGN)
            #endif
            
            self.unsafeSend { _ in
                for task in self.activeTasks where task.response == response {
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
                                           timeoutRetry: timeoutRetry - 1,
                                           returnCallback)
                        }
                    }
                    return
                }
                
                returnCallback(data, response, error)
            }
        }
        waitingTasks.append(task)
        self.checkForMoreTasks()
    }
}
