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

// MainActor-isolated type — verifies nonisolated properties work correctly
@MainActor
@Loggable(.internal)
class MainActorService {
    func performTask() {
        #log(.info, "MainActor task started")
    }

    nonisolated func backgroundLog() {
        #log(.debug, "Background log from MainActor type")
    }
}

// Multiple named categories — call sites select one via a key-path literal.
@Loggable(categories: "network", "persistence")
struct MultiCategoryService {
    func run() {
        #log(.debug, category: \.network, "request issued")
        #log(.info, category: \.persistence, "saved \(42, privacy: .public) records")
        #log(.error, "falls back to the type-level default category")
    }
}

// Categories combined with access level and custom subsystem.
@Loggable(.internal, subsystem: "com.example.app", categories: "ui", "database")
final class CategorizedController {
    func refresh() {
        #log(.info, category: \.ui, "refresh started")
        #log(.debug, category: \.database, "query executed \(3, privacy: .public) times")
    }
}

// MARK: - Protocol verification

// Applied to a protocol — generates a sibling extension with default impls
// keyed by each conforming type's metatype identity at runtime.
@Loggable(.internal)
protocol LoggableProtocol { }

struct ConformingService: LoggableProtocol {
    func work() {
        #log(.info, "Conforming service running")
    }
}

// Custom subsystem / category on a protocol.
@Loggable(.internal, subsystem: "com.example.networking", category: "Networking")
protocol NetworkingChannel { }

final class HTTPClient: NetworkingChannel {
    func fetch() {
        #log(.debug, "HTTP request issued")
    }
}

// Frozen variant — conforming types cannot override and protocol-extension call
// sites resolve statically to the default implementation.
@Loggable(asProtocolRequirement: false)
protocol FrozenLog { }

struct FixedReporter: FrozenLog {
    func report() {
        #log(.info, "FixedReporter using frozen default logger")
    }
}

print(URL(fileURLWithPath: "/Users/JH/Desktop").isWritable as Any)

let desktopURL = URL(fileURLWithPath: "/Users/JH/Desktop")
let (size, created, modified, isDir) = desktopURL.box.resourceValues(
    \.fileSize,
    \.creationDate,
    \.contentModificationDate,
    \.isDirectory
)
print("fileSize=\(size as Any), created=\(created as Any), modified=\(modified as Any), isDir=\(isDir as Any)")

// MARK: - @Keychain macro verification

private let exampleService = "com.frameworktoolbox.example"

final class KeychainExample {
    // Primitives encode without going through JSON.
    @Keychain(key: "accessToken", service: exampleService)
    var accessToken: String = ""

    @Keychain(key: "launchCount", service: exampleService, synchronizable: false)
    var launchCount: Int = 0

    @Keychain(key: "biometricsEnabled", service: exampleService)
    var biometricsEnabled: Bool = false

    // Optional types: writing nil deletes the underlying Keychain item.
    @Keychain(key: "refreshToken", service: exampleService)
    var refreshToken: String? = nil

    // Public properties also expose a public publisher.
    @Keychain(key: "lastSyncDate", service: exampleService)
    public var lastSyncDate: Date = Date(timeIntervalSince1970: 0)
}

// User-defined Codable types opt in via KeychainCodableStorable.
struct KeychainExamplePreferences: KeychainCodableStorable {
    var theme: String
    var notificationsEnabled: Bool
}

final class KeychainPreferencesStore {
    @Keychain(key: "preferences", service: exampleService)
    var preferences: KeychainExamplePreferences = .init(theme: "system", notificationsEnabled: true)
}

// Reference the types so the compiler proves the macro expansion type-checks
// without actually touching Keychain Services at startup.
_ = KeychainExample.self
_ = KeychainPreferencesStore.self

// MARK: - @UserDefault macro verification

final class UserDefaultExample {
    @UserDefault(key: "username")
    var username: String = ""

    @UserDefault(key: "launchCount")
    var launchCount: Int = 0

    @UserDefault(key: "darkModeEnabled")
    var darkModeEnabled: Bool = false

    // Optional types: writing nil calls removeObject(forKey:).
    @UserDefault(key: "refreshToken")
    var refreshToken: String? = nil

    // Suite-backed storage for app-group sharing.
    @UserDefault(key: "sharedToken", suite: "group.com.frameworktoolbox.example")
    var sharedToken: String = ""

    // Public properties also expose a public publisher.
    @UserDefault(key: "lastSyncDate")
    public var lastSyncDate: Date = Date(timeIntervalSince1970: 0)
}

// User-defined Codable types opt in via UserDefaultCodableStorable.
struct UserDefaultExamplePreferences: UserDefaultCodableStorable {
    var theme: String
    var notificationsEnabled: Bool
}

final class UserDefaultPreferencesStore {
    @UserDefault(key: "preferences")
    var preferences: UserDefaultExamplePreferences = .init(theme: "system", notificationsEnabled: true)
}

_ = UserDefaultExample.self
_ = UserDefaultPreferencesStore.self
