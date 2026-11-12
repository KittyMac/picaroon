import Foundation
import Flynn

internal var picaroonCoreCount: Int {
    Flynn.startup()
    return Flynn.cores
}
