@testable import FoundationToolbox
import Foundation
import Testing

// Pins the predefined messages in `FoundationMessages/` to Foundation's own.
//
// Where Foundation's exist — the 26 releases, so this machine — each message is
// compared with its Foundation counterpart: the same name, the same message out
// of the same notification, the same notification out of the same message.
// That is the whole contract, and it is what reverse engineering Foundation's
// implementation was for; a test that restated the expected values here would
// only pin this copy to itself.
//
// Below 26 the comparisons cannot run and are skipped. The undo manager test
// below runs everywhere: it checks that the notifications the system really
// posts reach backport observers at all.
@Suite("NotificationCenterBackport Foundation messages", notificationCenterBackportTimeLimit)
private struct NotificationCenterBackportFoundationMessagesTests {

    // MARK: - Compared with Foundation's

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @MainActor
    @Test func undoManagerMessagesMatchFoundation() {
        let undoManager = UndoManager()

        expectEmptyMainActorMessage(UndoManager.Backport.WillUndoChangeMessage.self, matches: UndoManager.WillUndoChangeMessage.self, subject: undoManager)
        expectEmptyMainActorMessage(UndoManager.Backport.WillRedoChangeMessage.self, matches: UndoManager.WillRedoChangeMessage.self, subject: undoManager)
        expectEmptyMainActorMessage(UndoManager.Backport.CheckpointMessage.self, matches: UndoManager.CheckpointMessage.self, subject: undoManager)
        expectEmptyMainActorMessage(UndoManager.Backport.DidOpenUndoGroupMessage.self, matches: UndoManager.DidOpenUndoGroupMessage.self, subject: undoManager)
        expectEmptyMainActorMessage(UndoManager.Backport.WillCloseUndoGroupMessage.self, matches: UndoManager.WillCloseUndoGroupMessage.self, subject: undoManager)

        let discardabilityUserInfos: [[AnyHashable: Any]?] = [
            nil,
            [NSUndoManagerGroupIsDiscardableKey: true],
            [NSUndoManagerGroupIsDiscardableKey: false],
            [NSUndoManagerGroupIsDiscardableKey: NSNumber(value: true)],
            [NSUndoManagerGroupIsDiscardableKey: NSNumber(value: 1)],
            [NSUndoManagerGroupIsDiscardableKey: NSNumber(value: 2)],
            [NSUndoManagerGroupIsDiscardableKey: "true"],
            ["groupIsDiscardable": true],
        ]
        let discardabilityNotifications = probeNotifications(subject: undoManager)
            + discardabilityUserInfos.map { Notification(name: .NSUndoManagerDidUndoChange, object: undoManager, userInfo: $0) }

        expectMainActorMessage(
            UndoManager.Backport.DidUndoChangeMessage.self,
            matches: UndoManager.DidUndoChangeMessage.self,
            convertedFrom: discardabilityNotifications,
            sending: [
                (.init(groupIsDiscardable: true), .init(groupIsDiscardable: true)),
                (.init(groupIsDiscardable: false), .init(groupIsDiscardable: false)),
            ],
            comparing: { "\($0.groupIsDiscardable)" },
            { "\($0.groupIsDiscardable)" }
        )
        expectMainActorMessage(
            UndoManager.Backport.DidRedoChangeMessage.self,
            matches: UndoManager.DidRedoChangeMessage.self,
            convertedFrom: discardabilityNotifications,
            sending: [
                (.init(groupIsDiscardable: true), .init(groupIsDiscardable: true)),
                (.init(groupIsDiscardable: false), .init(groupIsDiscardable: false)),
            ],
            comparing: { "\($0.groupIsDiscardable)" },
            { "\($0.groupIsDiscardable)" }
        )
        expectMainActorMessage(
            UndoManager.Backport.DidCloseUndoGroupMessage.self,
            matches: UndoManager.DidCloseUndoGroupMessage.self,
            convertedFrom: discardabilityNotifications,
            sending: [
                (.init(groupIsDiscardable: true), .init(groupIsDiscardable: true)),
                (.init(groupIsDiscardable: false), .init(groupIsDiscardable: false)),
            ],
            comparing: { "\($0.groupIsDiscardable)" },
            { "\($0.groupIsDiscardable)" }
        )
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @MainActor
    @Test func valueTypeMessagesMatchFoundation() {
        expectEmptyMainActorMessage(Date.Backport.SystemClockDidChangeMessage.self, matches: Date.SystemClockDidChangeMessage.self, subject: nil)
        expectEmptyMainActorMessage(Locale.Backport.CurrentLocaleDidChangeMessage.self, matches: Locale.CurrentLocaleDidChangeMessage.self, subject: nil)
        expectEmptyAsyncMessage(Calendar.Backport.CalendarDayChangedMessage.self, matches: Calendar.CalendarDayChangedMessage.self, subject: nil)

        // The system posts the previous time zone as the object.
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let timeZoneObjects: [Any] = [tokyo, NSTimeZone(name: "Europe/Paris")!, "Asia/Tokyo", NSObject()]
        let timeZoneNotifications = probeNotifications(subject: nil)
            + timeZoneObjects.map { Notification(name: .NSSystemTimeZoneDidChange, object: $0) }

        expectMainActorMessage(
            TimeZone.Backport.SystemTimeZoneDidChangeMessage.self,
            matches: TimeZone.SystemTimeZoneDidChangeMessage.self,
            convertedFrom: timeZoneNotifications,
            sending: [
                (.init(previousTimeZone: tokyo), .init(previousTimeZone: tokyo)),
                (.init(previousTimeZone: nil), .init(previousTimeZone: nil)),
            ],
            comparing: { $0.previousTimeZone?.identifier ?? "nil" },
            { $0.previousTimeZone?.identifier ?? "nil" }
        )
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test func fileHandleMessagesMatchFoundation() {
        let fileHandle = FileHandle.nullDevice
        let errorKey = "NSFileHandleError"

        expectEmptyAsyncMessage(FileHandle.Backport.DataAvailableMessage.self, matches: FileHandle.DataAvailableMessage.self, subject: fileHandle)

        // An error code wins over an item, an unknown code is skipped, and
        // neither present is no message.
        let resultUserInfos: (_ itemKey: String, _ item: Any) -> [[AnyHashable: Any]?] = { itemKey, item in
            [
                nil,
                [:],
                [itemKey: item],
                [itemKey: "not the item"],
                [errorKey: NSNumber(value: POSIXErrorCode.EBADF.rawValue)],
                [errorKey: Int(POSIXErrorCode.ECONNRESET.rawValue)],
                [errorKey: NSNumber(value: 100_000)],
                [errorKey: NSNumber(value: 0)],
                [errorKey: "9"],
                [errorKey: NSNumber(value: POSIXErrorCode.EBADF.rawValue), itemKey: item],
                [errorKey: NSNumber(value: 100_000), itemKey: item],
            ]
        }

        expectAsyncMessage(
            FileHandle.Backport.ConnectionAcceptedMessage.self,
            matches: FileHandle.ConnectionAcceptedMessage.self,
            convertedFrom: probeNotifications(subject: fileHandle) + resultUserInfos(NSFileHandleNotificationFileHandleItem, fileHandle).map {
                Notification(name: .NSFileHandleConnectionAccepted, object: fileHandle, userInfo: $0)
            },
            sending: [
                (.init(fileHandleItem: .success(fileHandle)), .init(fileHandleItem: .success(fileHandle))),
                (.init(fileHandleItem: .failure(POSIXError(.EBADF))), .init(fileHandleItem: .failure(POSIXError(.EBADF)))),
            ],
            comparing: { describe($0.fileHandleItem) },
            { describe($0.fileHandleItem) }
        )

        let data = Data([0x46, 0x54, 0x42])
        let dataNotifications: (Notification.Name) -> [Notification] = { name in
            probeNotifications(subject: fileHandle)
                + resultUserInfos(NSFileHandleNotificationDataItem, data).map { Notification(name: name, object: fileHandle, userInfo: $0) }
                + [Notification(name: name, object: fileHandle, userInfo: [NSFileHandleNotificationDataItem: data as NSData])]
        }
        let dataMessages: [Result<Data, POSIXError>] = [.success(data), .success(Data()), .failure(POSIXError(.EIO))]

        expectAsyncMessage(
            FileHandle.Backport.ReadToEndOfFileCompletionMessage.self,
            matches: FileHandle.ReadToEndOfFileCompletionMessage.self,
            convertedFrom: dataNotifications(.NSFileHandleReadToEndOfFileCompletion),
            sending: dataMessages.map { (.init(dataItem: $0), .init(dataItem: $0)) },
            comparing: { describe($0.dataItem) },
            { describe($0.dataItem) }
        )
        expectAsyncMessage(
            FileHandle.Backport.ReadCompletionMessage.self,
            matches: FileHandle.ReadCompletionMessage.self,
            convertedFrom: dataNotifications(FileHandle.readCompletionNotification),
            sending: dataMessages.map { (.init(dataItem: $0), .init(dataItem: $0)) },
            comparing: { describe($0.dataItem) },
            { describe($0.dataItem) }
        )
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @MainActor
    @Test func remainingMessagesMatchFoundation() {
        expectEmptyAsyncMessage(HTTPCookieStorage.Backport.CookiesChangedMessage.self, matches: HTTPCookieStorage.CookiesChangedMessage.self, subject: HTTPCookieStorage.shared)
        expectEmptyAsyncMessage(NSMetadataQuery.Backport.DidFinishGatheringMessage.self, matches: NSMetadataQuery.DidFinishGatheringMessage.self, subject: nil)
        expectEmptyAsyncMessage(NSMetadataQuery.Backport.DidStartGatheringMessage.self, matches: NSMetadataQuery.DidStartGatheringMessage.self, subject: nil)
        expectEmptyAsyncMessage(ProcessInfo.Backport.PowerStateDidChangeMessage.self, matches: ProcessInfo.PowerStateDidChangeMessage.self, subject: ProcessInfo.processInfo)
        expectEmptyAsyncMessage(ProcessInfo.Backport.ThermalStateDidChangeMessage.self, matches: ProcessInfo.ThermalStateDidChangeMessage.self, subject: ProcessInfo.processInfo)
        expectEmptyAsyncMessage(Bundle.Backport.DidLoadMessage.self, matches: Bundle.DidLoadMessage.self, subject: Bundle.main)
        expectEmptyAsyncMessage(UserDefaults.Backport.DidChangeMessage.self, matches: UserDefaults.DidChangeMessage.self, subject: UserDefaults.standard)
        expectEmptyMainActorMessage(UserDefaults.Backport.SizeLimitExceededMessage.self, matches: UserDefaults.SizeLimitExceededMessage.self, subject: UserDefaults.standard)
        expectEmptyAsyncMessage(Port.Backport.DidBecomeInvalidMessage.self, matches: Port.DidBecomeInvalidMessage.self, subject: nil)
        expectEmptyMainActorMessage(FileManager.Backport.UbiquityIdentityDidChangeMessage.self, matches: FileManager.UbiquityIdentityDidChangeMessage.self, subject: FileManager.default)
        expectEmptyMainActorMessage(NSExtensionContext.Backport.DidBecomeActiveMessage.self, matches: NSExtensionContext.DidBecomeActiveMessage.self, subject: nil)
        expectEmptyMainActorMessage(NSExtensionContext.Backport.DidEnterBackgroundMessage.self, matches: NSExtensionContext.DidEnterBackgroundMessage.self, subject: nil)
        expectEmptyMainActorMessage(NSExtensionContext.Backport.WillEnterForegroundMessage.self, matches: NSExtensionContext.WillEnterForegroundMessage.self, subject: nil)
        expectEmptyMainActorMessage(NSExtensionContext.Backport.WillResignActiveMessage.self, matches: NSExtensionContext.WillResignActiveMessage.self, subject: nil)
        #if os(macOS)
        expectEmptyAsyncMessage(Process.Backport.DidTerminateMessage.self, matches: Process.DidTerminateMessage.self, subject: nil)
        #endif
    }

    // MARK: - Posted by the system

    // The comparisons above cannot run below 26. This one can: every message an
    // undo manager posts has to arrive at a backport observer, which takes the
    // right name and a `makeMessage(_:)` that does not return `nil`. The types
    // are spelled out because the shorthand picks Foundation's messages
    // wherever they are available, which would leave the backport untested.
    @MainActor
    @Test func undoManagerNotificationsReachBackportObservers() {
        let center = NotificationCenter.default
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let counter = UndoableCounter()
        let log = ReceivedMessageLog()

        let tokens = [
            center.addObserver(of: undoManager, for: UndoManager.Backport.WillUndoChangeMessage.self) { _ in log.record("willUndoChange") },
            center.addObserver(of: undoManager, for: UndoManager.Backport.DidUndoChangeMessage.self) { _ in log.record("didUndoChange") },
            center.addObserver(of: undoManager, for: UndoManager.Backport.WillRedoChangeMessage.self) { _ in log.record("willRedoChange") },
            center.addObserver(of: undoManager, for: UndoManager.Backport.DidRedoChangeMessage.self) { _ in log.record("didRedoChange") },
            center.addObserver(of: undoManager, for: UndoManager.Backport.CheckpointMessage.self) { _ in log.record("checkpoint") },
            center.addObserver(of: undoManager, for: UndoManager.Backport.DidOpenUndoGroupMessage.self) { _ in log.record("didOpenUndoGroup") },
            center.addObserver(of: undoManager, for: UndoManager.Backport.WillCloseUndoGroupMessage.self) { _ in log.record("willCloseUndoGroup") },
            center.addObserver(of: undoManager, for: UndoManager.Backport.DidCloseUndoGroupMessage.self) { message in
                log.record("didCloseUndoGroup discardable: \(message.groupIsDiscardable)")
            },
        ]

        undoManager.beginUndoGrouping()
        counter.increment(registeringWith: undoManager)
        undoManager.setActionIsDiscardable(true)
        undoManager.endUndoGrouping()
        undoManager.undo()
        undoManager.redo()

        #expect(counter.value == 1)
        #expect(Set(log.entries) == [
            "willUndoChange", "didUndoChange", "willRedoChange", "didRedoChange", "checkpoint",
            "didOpenUndoGroup", "willCloseUndoGroup", "didCloseUndoGroup discardable: true",
        ])
        withExtendedLifetime(tokens) {}
    }
}

// MARK: - Comparison helpers

// Notifications every message is converted from: its own name, bare and with
// the subject as object, with user info it does not read, and one that is
// plainly a different notification.
private func probeNotifications(subject: Any?) -> [Notification] {
    [
        Notification(name: Notification.Name("FrameworkToolboxProbeNotification")),
        Notification(name: Notification.Name("FrameworkToolboxProbeNotification"), object: subject, userInfo: ["unrelated": 1]),
        Notification(name: .NSUndoManagerCheckpoint, object: NSObject(), userInfo: [:]),
    ]
}

// What a test can compare of a notification: its name, its object, and each
// user info entry together with the dynamic type of its value — Foundation
// writes `Data`, not `NSData`, and an `NSNumber` that bridges either way.
private struct NotificationSnapshot: Equatable, CustomStringConvertible {
    let name: Notification.Name
    let object: String
    let userInfo: [String: String]?

    init(_ notification: Notification) {
        name = notification.name
        object = notification.object.map { "\(type(of: $0)) \($0)" } ?? "nil"
        userInfo = notification.userInfo.map { userInfo in
            Dictionary(uniqueKeysWithValues: userInfo.map { key, value in ("\(key)", "\(type(of: value)) \(value)") })
        }
    }

    var description: String {
        "\(name.rawValue), object: \(object), userInfo: \(userInfo.map { "\($0)" } ?? "nil")"
    }
}

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
@MainActor
private func expectMainActorMessage<BackportMessage: NotificationCenter.Backport.MainActorMessage, FoundationMessage: NotificationCenter.MainActorMessage>(
    _ backportType: BackportMessage.Type,
    matches foundationType: FoundationMessage.Type,
    convertedFrom notifications: [Notification],
    sending messages: [(BackportMessage, FoundationMessage)],
    comparing backportPayload: (BackportMessage) -> String,
    _ foundationPayload: (FoundationMessage) -> String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(BackportMessage.name == FoundationMessage.name, sourceLocation: sourceLocation)
    for notification in notifications + [Notification(name: FoundationMessage.name)] {
        #expect(
            BackportMessage.makeMessage(notification).map(backportPayload) == FoundationMessage.makeMessage(notification).map(foundationPayload),
            "converting \(NotificationSnapshot(notification))",
            sourceLocation: sourceLocation
        )
    }
    for (backportMessage, foundationMessage) in messages {
        #expect(
            NotificationSnapshot(BackportMessage.makeNotification(backportMessage)) == NotificationSnapshot(FoundationMessage.makeNotification(foundationMessage)),
            sourceLocation: sourceLocation
        )
    }
}

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
private func expectAsyncMessage<BackportMessage: NotificationCenter.Backport.AsyncMessage, FoundationMessage: NotificationCenter.AsyncMessage>(
    _ backportType: BackportMessage.Type,
    matches foundationType: FoundationMessage.Type,
    convertedFrom notifications: [Notification],
    sending messages: [(BackportMessage, FoundationMessage)],
    comparing backportPayload: (BackportMessage) -> String,
    _ foundationPayload: (FoundationMessage) -> String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(BackportMessage.name == FoundationMessage.name, sourceLocation: sourceLocation)
    for notification in notifications + [Notification(name: FoundationMessage.name)] {
        #expect(
            BackportMessage.makeMessage(notification).map(backportPayload) == FoundationMessage.makeMessage(notification).map(foundationPayload),
            "converting \(NotificationSnapshot(notification))",
            sourceLocation: sourceLocation
        )
    }
    for (backportMessage, foundationMessage) in messages {
        #expect(
            NotificationSnapshot(BackportMessage.makeNotification(backportMessage)) == NotificationSnapshot(FoundationMessage.makeNotification(foundationMessage)),
            sourceLocation: sourceLocation
        )
    }
}

// A message without properties: the same name, a message out of every
// notification (or none, if Foundation's made none), and the same notification
// out of the protocol's default `makeNotification(_:)`.
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
@MainActor
private func expectEmptyMainActorMessage<BackportMessage: NotificationCenter.Backport.MainActorMessage & EmptyMessage, FoundationMessage: NotificationCenter.MainActorMessage & EmptyMessage>(
    _ backportType: BackportMessage.Type,
    matches foundationType: FoundationMessage.Type,
    subject: Any?,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    expectMainActorMessage(
        backportType,
        matches: foundationType,
        convertedFrom: probeNotifications(subject: subject),
        sending: [(BackportMessage(), FoundationMessage())],
        comparing: { _ in "" },
        { _ in "" },
        sourceLocation: sourceLocation
    )
}

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
private func expectEmptyAsyncMessage<BackportMessage: NotificationCenter.Backport.AsyncMessage & EmptyMessage, FoundationMessage: NotificationCenter.AsyncMessage & EmptyMessage>(
    _ backportType: BackportMessage.Type,
    matches foundationType: FoundationMessage.Type,
    subject: Any?,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    expectAsyncMessage(
        backportType,
        matches: foundationType,
        convertedFrom: probeNotifications(subject: subject),
        sending: [(BackportMessage(), FoundationMessage())],
        comparing: { _ in "" },
        { _ in "" },
        sourceLocation: sourceLocation
    )
}

private func describe(_ item: Result<FileHandle, POSIXError>) -> String {
    switch item {
    case .success(let fileHandle): "success \(ObjectIdentifier(fileHandle))"
    case .failure(let error): "failure \(error.code.rawValue) \(error.userInfo.count)"
    }
}

private func describe(_ item: Result<Data, POSIXError>) -> String {
    switch item {
    case .success(let data): "success \(Array(data))"
    case .failure(let error): "failure \(error.code.rawValue) \(error.userInfo.count)"
    }
}

// The messages without properties, on both sides, so the helpers above can
// build one of each.
private protocol EmptyMessage {
    init()
}

extension UndoManager.Backport.WillUndoChangeMessage: EmptyMessage {}
extension UndoManager.Backport.WillRedoChangeMessage: EmptyMessage {}
extension UndoManager.Backport.CheckpointMessage: EmptyMessage {}
extension UndoManager.Backport.DidOpenUndoGroupMessage: EmptyMessage {}
extension UndoManager.Backport.WillCloseUndoGroupMessage: EmptyMessage {}
extension Date.Backport.SystemClockDidChangeMessage: EmptyMessage {}
extension Locale.Backport.CurrentLocaleDidChangeMessage: EmptyMessage {}
extension Calendar.Backport.CalendarDayChangedMessage: EmptyMessage {}
extension FileHandle.Backport.DataAvailableMessage: EmptyMessage {}
extension HTTPCookieStorage.Backport.CookiesChangedMessage: EmptyMessage {}
extension NSMetadataQuery.Backport.DidFinishGatheringMessage: EmptyMessage {}
extension NSMetadataQuery.Backport.DidStartGatheringMessage: EmptyMessage {}
@available(macOS 12, *)
extension ProcessInfo.Backport.PowerStateDidChangeMessage: EmptyMessage {}
extension ProcessInfo.Backport.ThermalStateDidChangeMessage: EmptyMessage {}
extension Bundle.Backport.DidLoadMessage: EmptyMessage {}
extension UserDefaults.Backport.DidChangeMessage: EmptyMessage {}
extension UserDefaults.Backport.SizeLimitExceededMessage: EmptyMessage {}
extension Port.Backport.DidBecomeInvalidMessage: EmptyMessage {}
extension FileManager.Backport.UbiquityIdentityDidChangeMessage: EmptyMessage {}
extension NSExtensionContext.Backport.DidBecomeActiveMessage: EmptyMessage {}
extension NSExtensionContext.Backport.DidEnterBackgroundMessage: EmptyMessage {}
extension NSExtensionContext.Backport.WillEnterForegroundMessage: EmptyMessage {}
extension NSExtensionContext.Backport.WillResignActiveMessage: EmptyMessage {}

@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UndoManager.WillUndoChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UndoManager.WillRedoChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UndoManager.CheckpointMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UndoManager.DidOpenUndoGroupMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UndoManager.WillCloseUndoGroupMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension Date.SystemClockDidChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension Locale.CurrentLocaleDidChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension Calendar.CalendarDayChangedMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension FileHandle.DataAvailableMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension HTTPCookieStorage.CookiesChangedMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension NSMetadataQuery.DidFinishGatheringMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension NSMetadataQuery.DidStartGatheringMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension ProcessInfo.PowerStateDidChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension ProcessInfo.ThermalStateDidChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension Bundle.DidLoadMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UserDefaults.DidChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension UserDefaults.SizeLimitExceededMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension Port.DidBecomeInvalidMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension FileManager.UbiquityIdentityDidChangeMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension NSExtensionContext.DidBecomeActiveMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension NSExtensionContext.DidEnterBackgroundMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension NSExtensionContext.WillEnterForegroundMessage: EmptyMessage {}
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
extension NSExtensionContext.WillResignActiveMessage: EmptyMessage {}

#if os(macOS)
extension Process.Backport.DidTerminateMessage: EmptyMessage {}
@available(macOS 26, *)
extension Process.DidTerminateMessage: EmptyMessage {}
#endif

// MARK: - Undo manager fixtures

@MainActor
private final class ReceivedMessageLog {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

// Registers its own inverse on every change, so that an undo leaves something
// to redo.
@MainActor
private final class UndoableCounter {
    private(set) var value = 0

    func increment(registeringWith undoManager: UndoManager) {
        value += 1
        undoManager.registerUndo(withTarget: self) { counter in
            counter.decrement(registeringWith: undoManager)
        }
    }

    func decrement(registeringWith undoManager: UndoManager) {
        value -= 1
        undoManager.registerUndo(withTarget: self) { counter in
            counter.increment(registeringWith: undoManager)
        }
    }
}
