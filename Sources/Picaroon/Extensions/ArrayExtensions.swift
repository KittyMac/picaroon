import Foundation

class BoxedArray<T>: MutableCollection {
    var array: [T]

    init() {
        array = [T]()
    }

    var startIndex: Int {
        return array.startIndex
    }
    var endIndex: Int {
        return array.endIndex
    }
    func index(after idx: Int) -> Int {
        array.index(after: idx)
    }

    func append(_ value: T) {
        array.append(value)
    }

    subscript (index: Int) -> T {
        get { return array[index] }
        set(newValue) { array[index] = newValue }
    }
}

class EncodableBoxedArray<T: Encodable>: MutableCollection, Encodable {
    var array: [T]

    init() {
        array = [T]()
    }

    var startIndex: Int {
        return array.startIndex
    }
    var endIndex: Int {
        return array.endIndex
    }
    func index(after idx: Int) -> Int {
        array.index(after: idx)
    }

    func append(_ value: T) {
        array.append(value)
    }

    subscript (index: Int) -> T {
        get { return array[index] }
        set(newValue) { array[index] = newValue }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array where Element: Equatable {
    mutating func removeOne (_ element: Element) {
        if let idx = firstIndex(of: element) {
            remove(at: idx)
        }
    }

    mutating func removeLast (_ element: Element) {
        if let idx = lastIndex(of: element) {
            remove(at: idx)
        }
    }

    mutating func removeAll (_ element: Element) {
        removeAll { $0 == element }
    }
}

extension BoxedArray where Element: Equatable {
    func removeOne (_ element: Element) {
        if let idx = firstIndex(of: element) {
            array.remove(at: idx)
        }
    }

    func removeAll (_ element: Element) {
        array.removeAll { $0 == element }
    }
}
