import Foundation
import os
import FoundationToolbox

// MARK: - OSAllocatedUnfairLock macro verification

@available(SwiftStdlib 5.7, *)
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

if #available(SwiftStdlib 5.7, *) {
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

// Named categories declared once as static members — call sites reference
// them with leading-dot syntax and full autocomplete.
extension LogCategory {
    static let network = LogCategory("network")
    static let persistence = LogCategory("persistence")
}

@Loggable
struct MultiCategoryService {
    func run() {
        #log(.debug, category: .network, "request issued")
        #log(.info, category: .persistence, "saved \(42, privacy: .public) records")
        #log(.error, "falls back to the type-level default category")
    }
}

// Categories combined with access level and custom subsystem; any LogCategory
// expression is accepted, not just leading-dot references.
@Loggable(.internal, subsystem: "com.example.app")
final class CategorizedController {
    func refresh() {
        #log(.info, category: .network, "refresh started")
        #log(.debug, category: LogCategory("database"), "query executed \(3, privacy: .public) times")
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

// MARK: - `@Signpostable` / `#signpost` re-export (two hops)

// Two re-export hops away from where these are declared:
// `OSToolbox` → `SwiftStdlibToolbox` → `FoundationToolbox`. A bare
// `import FoundationToolbox` must still resolve the macros and their plugin.

@Signpostable
struct SignpostReExportProbeTwoHops {
    func measure() -> Int {
        #signpost(.event, category: .pointsOfInterest, "two hops")
        let interval = #signpost(.begin, "two hop interval", "at=\(Date(), privacy: .public)")
        #signpost(.end, interval)
        return #signpostInterval("two hop scoped") { 2 }
    }
}

print("signpost re-export (two hops):", SignpostReExportProbeTwoHops().measure())

// MARK: - `NotificationCenter.Backport` through the public interface

// The tests reach this API through `@testable import`, which would hide a
// declaration that forgot `public`. Every shape a caller writes is spelled out
// here against the plain import instead.

final class BackportExampleDocument {}

struct BackportExampleDocumentDidSave: NotificationCenter.Backport.MainActorMessage {
    typealias Subject = BackportExampleDocument
    var revision: Int
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<BackportExampleDocumentDidSave> {
    static var documentDidSave: Self { .init() }
}

struct BackportExampleDownloadDidFinish: NotificationCenter.Backport.AsyncMessage {
    typealias Subject = BackportExampleDocument
    var byteCount: Int
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<BackportExampleDownloadDidFinish> {
    static var downloadDidFinish: Self { .init() }
}

@MainActor
func demonstrateNotificationCenterBackport() -> Int {
    let center = NotificationCenter()
    let document = BackportExampleDocument()
    var savedRevisions: [Int] = []

    let tokens: [NotificationCenter.Backport.ObservationToken] = [
        center.addObserver(of: document, for: .documentDidSave) { message in savedRevisions.append(message.revision) },
        center.addObserver(of: BackportExampleDocument.self, for: .documentDidSave) { _ in },
        center.addObserver(of: document, for: BackportExampleDocumentDidSave.self) { _ in },
        center.addObserver(of: document, for: .downloadDidFinish) { message in _ = message.byteCount },
        center.addObserver(of: BackportExampleDocument.self, for: .downloadDidFinish) { _ in },
        center.addObserver(for: BackportExampleDownloadDidFinish.self) { _ in },
    ]

    center.post(BackportExampleDocumentDidSave(revision: 1), subject: document)
    center.post(BackportExampleDocumentDidSave(revision: 2))
    center.post(BackportExampleDownloadDidFinish(byteCount: 1), subject: document)
    center.post(BackportExampleDownloadDidFinish(byteCount: 2))

    for token in tokens {
        center.removeObserver(token)
    }
    return savedRevisions.count
}

// Compiled, not run: the three `messages(of:for:bufferSize:)` shapes and a
// hand-driven iterator.
func consumeNotificationCenterBackportMessages(from center: NotificationCenter, about document: BackportExampleDocument) async {
    for await message in center.messages(of: document, for: .downloadDidFinish) {
        _ = message.byteCount
        break
    }
    for await message in center.messages(of: BackportExampleDocument.self, for: .downloadDidFinish, bufferSize: 1) {
        _ = message.byteCount
        break
    }
    var iterator = center.messages(for: BackportExampleDownloadDidFinish.self).makeAsyncIterator()
    _ = await iterator.next()
}

// MARK: - Foundation's predefined messages through the public interface

// Compiled, not run. Outside an `#available` check for the 26 releases every
// shorthand below resolves to the backport, so each predefined message's
// identifier, properties and initializer are reached through the plain import.
@MainActor
func observeFoundationPredefinedMessages(in center: NotificationCenter) -> [NotificationCenter.Backport.ObservationToken] {
    var tokens: [NotificationCenter.Backport.ObservationToken] = []
    tokens.append(center.addObserver(of: UndoManager.self, for: .willUndoChange) { _ in })
    tokens.append(center.addObserver(of: UndoManager.self, for: .didUndoChange) { message in _ = message.groupIsDiscardable })
    tokens.append(center.addObserver(of: UndoManager.self, for: .willRedoChange) { _ in })
    tokens.append(center.addObserver(of: UndoManager.self, for: .didRedoChange) { message in _ = message.groupIsDiscardable })
    tokens.append(center.addObserver(of: UndoManager.self, for: .checkpoint) { _ in })
    tokens.append(center.addObserver(of: UndoManager.self, for: .didOpenUndoGroup) { _ in })
    tokens.append(center.addObserver(of: UndoManager.self, for: .didCloseUndoGroup) { message in _ = message.groupIsDiscardable })
    tokens.append(center.addObserver(of: UndoManager.self, for: .willCloseUndoGroup) { _ in })
    tokens.append(center.addObserver(of: HTTPCookieStorage.self, for: .cookiesChanged) { _ in })
    tokens.append(center.addObserver(of: NSMetadataQuery.self, for: .didFinishGathering) { _ in })
    tokens.append(center.addObserver(of: NSMetadataQuery.self, for: .didStartGathering) { _ in })
    tokens.append(center.addObserver(of: Calendar.self, for: .calendarDayChanged) { _ in })
    tokens.append(center.addObserver(of: Date.self, for: .systemClockDidChange) { _ in })
    tokens.append(center.addObserver(of: TimeZone.self, for: .systemTimeZoneDidChange) { message in _ = message.previousTimeZone })
    tokens.append(center.addObserver(of: ProcessInfo.self, for: .thermalStateDidChange) { _ in })
    tokens.append(center.addObserver(of: FileHandle.self, for: .connectionAccepted) { message in _ = message.fileHandleItem })
    tokens.append(center.addObserver(of: FileHandle.self, for: .dataAvailable) { _ in })
    tokens.append(center.addObserver(of: FileHandle.self, for: .readToEndOfFileCompletion) { message in _ = message.dataItem })
    tokens.append(center.addObserver(of: FileHandle.self, for: .readCompletion) { message in _ = message.dataItem })
    tokens.append(center.addObserver(of: Bundle.self, for: .didLoad) { _ in })
    tokens.append(center.addObserver(of: UserDefaults.self, for: .didChange) { _ in })
    tokens.append(center.addObserver(of: UserDefaults.self, for: .sizeLimitExceeded) { _ in })
    tokens.append(center.addObserver(of: Port.self, for: .didBecomeInvalid) { _ in })
    tokens.append(center.addObserver(of: Locale.self, for: .currentLocaleDidChange) { _ in })
    tokens.append(center.addObserver(of: FileManager.self, for: .ubiquityIdentityDidChange) { _ in })
    tokens.append(center.addObserver(of: NSExtensionContext.self, for: .didBecomeActive) { _ in })
    tokens.append(center.addObserver(of: NSExtensionContext.self, for: .didEnterBackground) { _ in })
    tokens.append(center.addObserver(of: NSExtensionContext.self, for: .willEnterForeground) { _ in })
    tokens.append(center.addObserver(of: NSExtensionContext.self, for: .willResignActive) { _ in })
    #if os(macOS)
    tokens.append(center.addObserver(of: Process.self, for: .didTerminate) { _ in })
    #endif
    return tokens
}

// The one predefined message that asks for more than the floor: its
// notification's constant is macOS 12.
@available(macOS 12, *)
func reachPowerStateMessage(in center: NotificationCenter) -> (NotificationCenter.Backport.ObservationToken, Notification) {
    (
        center.addObserver(of: ProcessInfo.self, for: .powerStateDidChange) { _ in },
        ProcessInfo.Backport.PowerStateDidChangeMessage.makeNotification(.init())
    )
}

@MainActor
func makeFoundationPredefinedNotifications(fileHandle: FileHandle) -> [Notification] {
    var notifications = [
        UndoManager.Backport.WillUndoChangeMessage.makeNotification(.init()),
        UndoManager.Backport.DidUndoChangeMessage.makeNotification(.init(groupIsDiscardable: true)),
        UndoManager.Backport.WillRedoChangeMessage.makeNotification(.init()),
        UndoManager.Backport.DidRedoChangeMessage.makeNotification(.init(groupIsDiscardable: true)),
        UndoManager.Backport.CheckpointMessage.makeNotification(.init()),
        UndoManager.Backport.DidOpenUndoGroupMessage.makeNotification(.init()),
        UndoManager.Backport.DidCloseUndoGroupMessage.makeNotification(.init(groupIsDiscardable: true)),
        UndoManager.Backport.WillCloseUndoGroupMessage.makeNotification(.init()),
        HTTPCookieStorage.Backport.CookiesChangedMessage.makeNotification(.init()),
        NSMetadataQuery.Backport.DidFinishGatheringMessage.makeNotification(.init()),
        NSMetadataQuery.Backport.DidStartGatheringMessage.makeNotification(.init()),
        Calendar.Backport.CalendarDayChangedMessage.makeNotification(.init()),
        Date.Backport.SystemClockDidChangeMessage.makeNotification(.init()),
        TimeZone.Backport.SystemTimeZoneDidChangeMessage.makeNotification(.init(previousTimeZone: .current)),
        ProcessInfo.Backport.ThermalStateDidChangeMessage.makeNotification(.init()),
        FileHandle.Backport.ConnectionAcceptedMessage.makeNotification(.init(fileHandleItem: .success(fileHandle))),
        FileHandle.Backport.DataAvailableMessage.makeNotification(.init()),
        FileHandle.Backport.ReadToEndOfFileCompletionMessage.makeNotification(.init(dataItem: .success(Data()))),
        FileHandle.Backport.ReadCompletionMessage.makeNotification(.init(dataItem: .failure(POSIXError(.EIO)))),
        Bundle.Backport.DidLoadMessage.makeNotification(.init()),
        UserDefaults.Backport.DidChangeMessage.makeNotification(.init()),
        UserDefaults.Backport.SizeLimitExceededMessage.makeNotification(.init()),
        Port.Backport.DidBecomeInvalidMessage.makeNotification(.init()),
        Locale.Backport.CurrentLocaleDidChangeMessage.makeNotification(.init()),
        FileManager.Backport.UbiquityIdentityDidChangeMessage.makeNotification(.init()),
        NSExtensionContext.Backport.DidBecomeActiveMessage.makeNotification(.init()),
        NSExtensionContext.Backport.DidEnterBackgroundMessage.makeNotification(.init()),
        NSExtensionContext.Backport.WillEnterForegroundMessage.makeNotification(.init()),
        NSExtensionContext.Backport.WillResignActiveMessage.makeNotification(.init()),
    ]
    #if os(macOS)
    notifications.append(Process.Backport.DidTerminateMessage.makeNotification(.init()))
    #endif
    return notifications
}

// Compiled, not run, and the guard for `@_disfavoredOverload` on every
// predefined identifier: where Foundation's own messages are available, each
// shorthand has to resolve to Foundation's, and it is ambiguous — so this
// fails to compile — for any identifier that lost the attribute. The results
// are discarded rather than collected, because a typed destination would pick
// the overload by itself and hide the ambiguity.
@MainActor
func observeThroughFoundationsOwnShorthand(in center: NotificationCenter) {
    guard #available(macOS 26, *) else { return }
    _ = center.addObserver(of: UndoManager.self, for: .willUndoChange) { _ in }
    _ = center.addObserver(of: UndoManager.self, for: .didUndoChange) { _ in }
    _ = center.addObserver(of: UndoManager.self, for: .willRedoChange) { _ in }
    _ = center.addObserver(of: UndoManager.self, for: .didRedoChange) { _ in }
    _ = center.addObserver(of: UndoManager.self, for: .checkpoint) { _ in }
    _ = center.addObserver(of: UndoManager.self, for: .didOpenUndoGroup) { _ in }
    _ = center.addObserver(of: UndoManager.self, for: .didCloseUndoGroup) { _ in }
    _ = center.addObserver(of: UndoManager.self, for: .willCloseUndoGroup) { _ in }
    _ = center.addObserver(of: HTTPCookieStorage.self, for: .cookiesChanged) { _ in }
    _ = center.addObserver(of: NSMetadataQuery.self, for: .didFinishGathering) { _ in }
    _ = center.addObserver(of: NSMetadataQuery.self, for: .didStartGathering) { _ in }
    _ = center.addObserver(of: Calendar.self, for: .calendarDayChanged) { _ in }
    _ = center.addObserver(of: Date.self, for: .systemClockDidChange) { _ in }
    _ = center.addObserver(of: TimeZone.self, for: .systemTimeZoneDidChange) { _ in }
    _ = center.addObserver(of: ProcessInfo.self, for: .powerStateDidChange) { _ in }
    _ = center.addObserver(of: ProcessInfo.self, for: .thermalStateDidChange) { _ in }
    _ = center.addObserver(of: FileHandle.self, for: .connectionAccepted) { _ in }
    _ = center.addObserver(of: FileHandle.self, for: .dataAvailable) { _ in }
    _ = center.addObserver(of: FileHandle.self, for: .readToEndOfFileCompletion) { _ in }
    _ = center.addObserver(of: FileHandle.self, for: .readCompletion) { _ in }
    _ = center.addObserver(of: Bundle.self, for: .didLoad) { _ in }
    _ = center.addObserver(of: UserDefaults.self, for: .didChange) { _ in }
    _ = center.addObserver(of: UserDefaults.self, for: .sizeLimitExceeded) { _ in }
    _ = center.addObserver(of: Port.self, for: .didBecomeInvalid) { _ in }
    _ = center.addObserver(of: Locale.self, for: .currentLocaleDidChange) { _ in }
    _ = center.addObserver(of: FileManager.self, for: .ubiquityIdentityDidChange) { _ in }
    _ = center.addObserver(of: NSExtensionContext.self, for: .didBecomeActive) { _ in }
    _ = center.addObserver(of: NSExtensionContext.self, for: .didEnterBackground) { _ in }
    _ = center.addObserver(of: NSExtensionContext.self, for: .willEnterForeground) { _ in }
    _ = center.addObserver(of: NSExtensionContext.self, for: .willResignActive) { _ in }
    #if os(macOS)
    _ = center.addObserver(of: Process.self, for: .didTerminate) { _ in }
    #endif
}

print("NotificationCenter.Backport messages observed:", MainActor.assumeIsolated { demonstrateNotificationCenterBackport() })
