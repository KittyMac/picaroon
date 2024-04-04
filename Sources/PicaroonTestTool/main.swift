import Flynn
import Foundation
import Hitch
import Picaroon

var waiting = 2048
for _ in 0..<2048 {
    HTTPSessionManager.shared.beNew(Flynn.any) { session in
        session.beRequest(url: "https://www.swift-linux.com",
                          httpMethod: "GET",
                          params: [:],
                          headers: [:],
                          cookies: nil,
                          timeoutRetry: nil,
                          proxy: nil,
                          body: nil,
                          Flynn.any) { data, response, error in
            if let error = error { fatalError(error) }
            if data == nil { fatalError("data is nil") }
            
            waiting -= 1
            
            print(waiting)
        }
    }
}

while waiting > 0 { Flynn.sleep(1) }
Flynn.shutdown()
