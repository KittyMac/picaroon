import Foundation
import Flynn
import Hitch

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal class HTTPTaskManager: Actor {
    internal static let shared = HTTPTaskManager()
    private override init() { }
    
    private let maxConcurrentTasks = 128
    
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
                            _ returnCallback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        let task = session.dataTask(with: request) { data, response, error in
            self.unsafeSend { _ in
                for task in self.activeTasks where task.response == response {
                    self.activeTasks.removeOne(task)
                    break
                }
                self.checkForMoreTasks()
                
                returnCallback(data, response, error)
            }
        }
        waitingTasks.append(task)
        self.checkForMoreTasks()
    }
}
