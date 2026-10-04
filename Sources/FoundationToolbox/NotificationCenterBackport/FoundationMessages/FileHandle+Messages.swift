import Foundation

// Foundation's predefined `FileHandle` messages. The conventions every file in
// `FoundationMessages/` follows are noted after `NotificationCenter.Backport`
// in `NotificationCenterBackport.swift`.

extension FileHandle {
    /// Backports of the messages Foundation declares on `FileHandle` from the
    /// 26 releases. See `NotificationCenter.Backport`.
    public enum Backport {}
}

extension FileHandle.Backport {
    /// A message a file handle sends when it creates a socket connection between two processes and creates a file handle for one end of the connection.
    public struct ConnectionAcceptedMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = FileHandle

        public static var name: Notification.Name {
            .NSFileHandleConnectionAccepted
        }

        /// A result instance that contains either the file handle representing the “near” end of a socket connection, or an error.
        public var fileHandleItem: Result<FileHandle, POSIXError>

        public init(fileHandleItem: Result<FileHandle, POSIXError>) {
            self.fileHandleItem = fileHandleItem
        }

        public static func makeMessage(_ notification: Notification) -> Self? {
            FileHandle.Backport.item(FileHandle.self, forKey: NSFileHandleNotificationFileHandleItem, in: notification)
                .map(Self.init(fileHandleItem:))
        }

        public static func makeNotification(_ message: Self) -> Notification {
            FileHandle.Backport.notification(named: name, item: message.fileHandleItem, forKey: NSFileHandleNotificationFileHandleItem)
        }
    }

    /// A message a file handle sends when it determines data is available for reading from a file or communications channel.
    public struct DataAvailableMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = FileHandle

        public static var name: Notification.Name {
            .NSFileHandleDataAvailable
        }

        public init() {}

        public static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }
    }

    /// A message a file handle sends when it reads all data in a file, or another process in a communication channel signals the end of the data.
    public struct ReadToEndOfFileCompletionMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = FileHandle

        public static var name: Notification.Name {
            .NSFileHandleReadToEndOfFileCompletion
        }

        /// A result that contains either the data read or an error.
        public var dataItem: Result<Data, POSIXError>

        public init(dataItem: Result<Data, POSIXError>) {
            self.dataItem = dataItem
        }

        public static func makeMessage(_ notification: Notification) -> Self? {
            FileHandle.Backport.item(Data.self, forKey: NSFileHandleNotificationDataItem, in: notification)
                .map(Self.init(dataItem:))
        }

        public static func makeNotification(_ message: Self) -> Notification {
            FileHandle.Backport.notification(named: name, item: message.dataItem, forKey: NSFileHandleNotificationDataItem)
        }
    }

    /// A message a file handle sends when it reads the data currently available in a file or a communication channel.
    public struct ReadCompletionMessage: NotificationCenter.Backport.AsyncMessage {
        public typealias Subject = FileHandle

        public static var name: Notification.Name {
            FileHandle.readCompletionNotification
        }

        /// A result instance containing either the data read from the file or connection, or else an error.
        public var dataItem: Result<Data, POSIXError>

        public init(dataItem: Result<Data, POSIXError>) {
            self.dataItem = dataItem
        }

        public static func makeMessage(_ notification: Notification) -> Self? {
            FileHandle.Backport.item(Data.self, forKey: NSFileHandleNotificationDataItem, in: notification)
                .map(Self.init(dataItem:))
        }

        public static func makeNotification(_ message: Self) -> Notification {
            FileHandle.Backport.notification(named: name, item: message.dataItem, forKey: NSFileHandleNotificationDataItem)
        }
    }
}

extension FileHandle.Backport {
    // The key a file handle notification carries an `errno` under when the
    // operation failed. The SDK declares no constant for it.
    fileprivate static let errorKey = "NSFileHandleError"

    // Foundation shares one implementation between the three messages that
    // carry a result. An error code wins over an item when both are present, a
    // code that is not a `POSIXErrorCode` is skipped as if it were absent, and
    // a notification with neither converts to no message at all. Written back,
    // `Data` stays a Swift `Data` and the code becomes an integer `NSNumber`.
    fileprivate static func item<Item>(
        _ itemType: Item.Type,
        forKey key: String,
        in notification: Notification
    ) -> Result<Item, POSIXError>? {
        guard let userInfo = notification.userInfo else { return nil }
        if let errorNumber = userInfo[errorKey] as? NSNumber,
           let errorCode = POSIXErrorCode(rawValue: errorNumber.int32Value) {
            return .failure(POSIXError(errorCode))
        }
        if let item = userInfo[key] as? Item {
            return .success(item)
        }
        return nil
    }

    fileprivate static func notification<Item>(
        named name: Notification.Name,
        item: Result<Item, POSIXError>,
        forKey key: String
    ) -> Notification {
        switch item {
        case .success(let value):
            return Notification(name: name, object: nil, userInfo: [key: value])
        case .failure(let error):
            return Notification(name: name, object: nil, userInfo: [errorKey: NSNumber(value: error.errorCode)])
        }
    }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<FileHandle.Backport.ConnectionAcceptedMessage> {
    /// The identifier of `FileHandle.Backport.ConnectionAcceptedMessage`.
    @_disfavoredOverload
    public static var connectionAccepted: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<FileHandle.Backport.DataAvailableMessage> {
    /// The identifier of `FileHandle.Backport.DataAvailableMessage`.
    @_disfavoredOverload
    public static var dataAvailable: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<FileHandle.Backport.ReadToEndOfFileCompletionMessage> {
    /// The identifier of `FileHandle.Backport.ReadToEndOfFileCompletionMessage`.
    @_disfavoredOverload
    public static var readToEndOfFileCompletion: Self { .init() }
}

extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<FileHandle.Backport.ReadCompletionMessage> {
    /// The identifier of `FileHandle.Backport.ReadCompletionMessage`.
    @_disfavoredOverload
    public static var readCompletion: Self { .init() }
}
