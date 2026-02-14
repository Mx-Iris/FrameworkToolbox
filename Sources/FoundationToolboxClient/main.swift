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

// Default access level (internal)
@Loggable
struct LoggableStruct {
    func doWork() {
        let value = 42
        #log(.debug, "Processing value: \(value, align: .left(columns: 4), privacy: .public)")
        
        #log(.info, "Processing value: \(value, privacy: .sensitive) \(value, privacy: .public)")
    }
}

// Explicit private access level
@Loggable(.private)
class LoggableClass {
    func handle() {
        #log(.info, "Handling request")
    }
}

// Public access level
@Loggable(.public)
struct PublicLoggableStruct {
    func logSomething() {
        #log(.info, "Public logging")
    }
}

// Internal access level
@Loggable(.internal)
struct InternalLoggableStruct {
    func logSomething() {
        #log(.info, "Internal logging")
    }
}
