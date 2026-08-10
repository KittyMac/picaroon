import Foundation
import Hitch

public extension Date {
    func toRFC2822() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE',' dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: self)
    }
    func toISO8601() -> String {
        return ISO8601DateFormatter().string(from: self)
    }
    func toISO8601Hitch() -> Hitch {
        return Hitch(string: ISO8601DateFormatter().string(from: self))
    }
}

public extension String {
    func fromRFC2822() -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE',' dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: self)
    }
}
