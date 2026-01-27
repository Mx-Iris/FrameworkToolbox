import Foundation
import os
import FoundationToolbox

// MARK: - OSAllocatedUnfairLock macro verification

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class UnfairLockClassDecl: Sendable {
    @OSAllocatedUnfairLock
    private var property: String!

    @OSAllocatedUnfairLock
    private weak var delegate: AnyObject!

    @OSAllocatedUnfairLock
    private var array: [String?] = []

    init(property: String) {
        self.property = property
    }
}

if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
    _ = UnfairLockClassDecl(property: "test")
}

// MARK: - Loggable & #log macro verification

@Loggable
struct LoggableStruct {
    func doWork() {
        let value = 42
        #log(.debug, "Processing value: \(value, privacy: .public)")
    }
}

@Loggable
class LoggableClass {
    func handle() {
        #log(.info, "Handling request")
    }
}
