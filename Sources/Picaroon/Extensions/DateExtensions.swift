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
        return Hitch(capacity: 32).append(iso8601: self).toString()
    }
    func toISO8601Hitch() -> Hitch {
        return Hitch(capacity: 32).append(iso8601: self)
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
