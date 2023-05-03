import Foundation
import Hitch

public extension Date {
    func toRFC2822() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: self)
    }
    func toISO8601() -> String {
        return ISO8601DateFormatter().string(from: self)
    }
    func toISO8601Hitch() -> Hitch {
        return Hitch(string: ISO8601DateFormatter().string(from: self))
    }
}
