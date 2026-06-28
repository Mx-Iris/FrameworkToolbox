import Foundation
import Combine
import Security
import Testing

@testable import FoundationToolbox

@Suite
struct KeychainStorageTests {

    // MARK: - Basic round trips

    @Test func defaultIsReturnedWhenItemAbsent() {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<String>(backend: backend, defaultValue: "default")
        #expect(storage.get() == "default")
    }

    @Test func stringRoundTrip() {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<String>(backend: backend, defaultValue: "default")

        storage.set("hello")
        #expect(storage.get() == "hello")

        storage.set("world")
        #expect(storage.get() == "world")
    }

    @Test func intRoundTrip() {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<Int>(backend: backend, defaultValue: 0)

        storage.set(42)
        #expect(storage.get() == 42)
    }

    @Test func cacheAvoidsRereadingBackend() {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<String>(backend: backend, defaultValue: "default")

        storage.set("hello")
        backend.resetReadCount()
        _ = storage.get()
        _ = storage.get()
        // Both reads hit the cache; backend.read() is not called again.
        #expect(backend.readCount == 0)
    }

    // MARK: - Optional / removal

    @Test func optionalNilDeletesItem() {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<String?>(backend: backend, defaultValue: nil)

        storage.set("active")
        #expect(storage.get() == "active")
        #expect(backend.storedData != nil)

        storage.set(nil)
        #expect(storage.get() == nil)
        #expect(backend.storedData == nil)
    }

    @Test func nestedOptionalInnerNilAlsoDeletes() {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<String??>(backend: backend, defaultValue: nil)

        storage.set(.some("x"))
        #expect(backend.storedData != nil)

        // .some(.none) — inner nil should be recognized via the recursive
        // _AnyOptionalStorableValue hook and trigger delete, not be encoded
        // as empty Data (which would round-trip to .some(.some(""))).
        storage.set(.some(.none))
        #expect(backend.storedData == nil)
    }

    // MARK: - Publisher

    @Test func publisherEmitsOnSet() async throws {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<Int>(backend: backend, defaultValue: 0)

        let received = ReceivedValues<Int>()
        let cancellable = storage.publisher.sink { received.append($0) }

        storage.set(1)
        storage.set(2)
        storage.set(3)

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(received.values == [1, 2, 3])
        cancellable.cancel()
    }

    @Test func publisherDoesNotEmitOnRead() async throws {
        let backend = InMemoryKeychainBackend()
        let storage = KeychainStorage<Int>(backend: backend, defaultValue: 5)

        let received = ReceivedValues<Int>()
        let cancellable = storage.publisher.sink { received.append($0) }

        _ = storage.get()
        _ = storage.get()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(received.values.isEmpty)
        cancellable.cancel()
    }

    // MARK: - Error reporting

    @Test func errorHandlerCapturesDecodeFailure() {
        let backend = InMemoryKeychainBackend()
        // Pre-seed bytes that won't decode as Int (which needs 8 bytes).
        backend.storedData = Data([0x01, 0x02])

        let storage = KeychainStorage<Int>(backend: backend, defaultValue: -1)

        let captured = ReceivedValues<KeychainError>()
        storage.errorHandler = { error in
            if let casted = error as? KeychainError {
                captured.append(casted)
            }
        }

        #expect(storage.get() == -1)
        #expect(captured.values.contains(.decodingFailed))
    }

    @Test func errorHandlerCapturesBackendFailure() {
        let backend = InMemoryKeychainBackend()
        backend.nextReadFailure = errSecAuthFailed

        let storage = KeychainStorage<String>(backend: backend, defaultValue: "default")

        let captured = ReceivedValues<KeychainError>()
        storage.errorHandler = { error in
            if let casted = error as? KeychainError {
                captured.append(casted)
            }
        }

        #expect(storage.get() == "default")
        #expect(captured.values.contains { error in
            if case .unhandled(let status) = error { return status == errSecAuthFailed }
            return false
        })
    }

    @Test func writeFailureDoesNotUpdateCacheOrPublish() async throws {
        let backend = InMemoryKeychainBackend()
        backend.nextWriteFailure = errSecAuthFailed

        let storage = KeychainStorage<String>(backend: backend, defaultValue: "default")

        let received = ReceivedValues<String>()
        let cancellable = storage.publisher.sink { received.append($0) }

        storage.set("hello")
        try await Task.sleep(nanoseconds: 20_000_000)
        // Failure path: nothing should reach the publisher and the cache must
        // not be polluted with the unwritten value.
        #expect(received.values.isEmpty)
        #expect(storage.get() == "default")
        cancellable.cancel()
    }

    // MARK: - Codable

    struct UserPreferences: KeychainCodableStorable, Equatable {
        var theme: String
        var notificationsEnabled: Bool
    }

    @Test func codableRoundTrip() {
        let backend = InMemoryKeychainBackend()
        let initial = UserPreferences(theme: "system", notificationsEnabled: false)
        let storage = KeychainStorage<UserPreferences>(backend: backend, defaultValue: initial)

        let updated = UserPreferences(theme: "dark", notificationsEnabled: true)
        storage.set(updated)
        #expect(storage.get() == updated)
    }
}

// MARK: - Test backends

private final class InMemoryKeychainBackend: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _storedData: Data?
    private var _readCount = 0
    private var _nextReadFailure: OSStatus?
    private var _nextWriteFailure: OSStatus?

    var storedData: Data? {
        get { lock.withLock { _storedData } }
        set { lock.withLock { _storedData = newValue } }
    }

    var readCount: Int { lock.withLock { _readCount } }

    var nextReadFailure: OSStatus? {
        get { lock.withLock { _nextReadFailure } }
        set { lock.withLock { _nextReadFailure = newValue } }
    }

    var nextWriteFailure: OSStatus? {
        get { lock.withLock { _nextWriteFailure } }
        set { lock.withLock { _nextWriteFailure = newValue } }
    }

    func resetReadCount() {
        lock.withLock { _readCount = 0 }
    }

    func read() -> KeychainReadResult {
        lock.withLock {
            _readCount += 1
            if let failure = _nextReadFailure {
                _nextReadFailure = nil
                return .failure(failure)
            }
            if let data = _storedData {
                return .success(data)
            }
            return .notFound
        }
    }

    func write(_ data: Data) -> KeychainWriteResult {
        lock.withLock {
            if let failure = _nextWriteFailure {
                _nextWriteFailure = nil
                return .failure(failure)
            }
            _storedData = data
            return .success
        }
    }

    func delete() -> KeychainDeleteResult {
        lock.withLock {
            if _storedData != nil {
                _storedData = nil
                return .success
            }
            return .notFound
        }
    }
}

private final class ReceivedValues<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var values: [Element] { lock.withLock { storage } }

    func append(_ value: Element) {
        lock.withLock { storage.append(value) }
    }
}
