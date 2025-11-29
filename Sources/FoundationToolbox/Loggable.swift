#if canImport(os)

import os.log
import Foundation

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public protocol Loggable {
    var logger: Logger { get }
    static var logger: Logger { get }
    static var subsystem: String { get }
    static var category: String { get }
}

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private var loggerByObjectIdentifier = Mutex<[ObjectIdentifier: Logger]>([:])

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension Loggable {
    public static var logger: Logger {
        let objectIdentifier = ObjectIdentifier(self)
        if let logger = loggerByObjectIdentifier.withLock({ $0[objectIdentifier] }) {
            return logger
        }

        let logger = Logger(subsystem: subsystem, category: category)
        loggerByObjectIdentifier.withLock {
            $0[objectIdentifier] = logger
        }
        return logger
    }

    public var logger: Logger { Self.logger }

    public static var category: String {
        .init(describing: self)
    }
    
    public static var subsystem: String {
        Bundle(for: BundleClass.self).bundleIdentifier ?? .init(describing: self)
    }
}

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension Loggable where Self: AnyObject {
    public static var subsystem: String {
        Bundle(for: self).bundleIdentifier ?? .init(describing: self)
    }
}

private final class BundleClass {}

#endif
