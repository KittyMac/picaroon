import Flynn
import Foundation
import Hitch
import Spanker

public extension HttpResponse {
    init(text: Hitch) {
        self.init(status: .ok, type: .txt, payload: text)
    }
    
    init(text: String) {
        self.init(status: .ok, type: .txt, payload: text.hitch())
    }
    
    init(javascript: Hitch) {
        self.init(status: .ok, type: .js, payload: javascript)
    }
    
    init(javascript: String) {
        self.init(status: .ok, type: .js, payload: javascript.hitch())
    }
    
    init(json: Hitch) {
        self.init(status: .ok, type: .json, payload: json)
    }
    
    init(json: String) {
        self.init(status: .ok, type: .json, payload: json.hitch())
    }
    
    init(json: JsonElement) {
        self.init(status: .ok, type: .json, payload: json.toHitch())
    }
}
