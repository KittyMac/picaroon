import Flynn
import Foundation
import Hitch

public extension HttpRequest {
    var multipartContent: [HttpRequest] {
        guard let contentType = contentType else { return [] }
        guard contentType.starts(with: "multipart/form-data") else { return [] }
        guard let content = content else { return [] }
        guard let buffer = content.raw() else { return [] }
        
        let startPtr = buffer
        let endPtr = buffer + content.count
        var ptr = startPtr

        var boundaryStartPtr = endPtr
        var boundaryEndPtr = endPtr

        var contents: [HttpRequest] = []

        // Find the boundary marker
        ptr = startPtr
        while ptr < endPtr {
            let size = ptr - startPtr

            if size >= 1 &&
                ptr[-1] == UInt8.minus &&
                ptr[0] == UInt8.minus {

                boundaryStartPtr = ptr - 1
                while ptr < endPtr {
                    if ptr.pointee == UInt8.carriageReturn || ptr.pointee == UInt8.newLine {
                        boundaryEndPtr = ptr
                        break
                    }
                    ptr += 1
                }
            }

            guard boundaryStartPtr == boundaryEndPtr else { break }

            ptr += 1
        }

        guard boundaryStartPtr < boundaryEndPtr else { return [] }

        // Using the boundary marker, parse out each http request separately
        ptr = startPtr
        while ptr < endPtr {
            var multipartStartPtr = endPtr
            var multipartEndPtr = endPtr

            // 0. Find the next boundary
            while ptr < endPtr {
                if ptr.pointee == boundaryStartPtr.pointee &&
                    endPtr - ptr >= boundaryEndPtr - boundaryStartPtr &&
                    memcmp(ptr, boundaryStartPtr, boundaryEndPtr - boundaryStartPtr) == 0 {
                    ptr += boundaryEndPtr - boundaryStartPtr
                    multipartStartPtr = ptr
                    break
                }
                ptr += 1
            }

            guard multipartStartPtr != endPtr else { break }

            // 1. Find the end of the multipart (ie the start of the next boundary
            while ptr < endPtr {
                if ptr.pointee == boundaryStartPtr.pointee &&
                    endPtr - ptr >= boundaryEndPtr - boundaryStartPtr &&
                    memcmp(ptr, boundaryStartPtr, boundaryEndPtr - boundaryStartPtr) == 0 {
                    multipartEndPtr = ptr - 2
                    break
                }
                ptr += 1
            }

            guard multipartEndPtr != endPtr else { break }

            if let request = HttpRequest(multipart: multipartStartPtr,
                                         size: multipartEndPtr - multipartStartPtr) {
                contents.append(request)
            }
        }

        return contents
    }

    func debug(start: UnsafePointer<UInt8>,
               end: UnsafePointer<UInt8>) {
        #if DEBUG
        let string = String(data: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: start),
                                       count: end - start,
                                       deallocator: .none), encoding: .utf8)!
        print("[\(string)]")
        #endif
    }
}
