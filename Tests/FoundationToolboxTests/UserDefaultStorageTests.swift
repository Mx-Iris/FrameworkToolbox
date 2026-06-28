import Foundation
import Combine
import Testing

@testable import FoundationToolbox

@Suite
struct UserDefaultStorageTests {

    // MARK: - Helpers

    /// Creates a storage instance backed by a freshly-generated suite name so
    /// tests stay isolated from one another and from `UserDefaults.standard`.
    /// Returns a cleanup closure that wipes the suite when the test ends.
    private func makeStorage<Value: UserDefaultStorable>(
        key: String = "value",
        defaultValue: Value
    ) -> (UserDefaultStorage<Value>, () -> Void) {
        let suiteName = "com.frameworktoolbox.test.\(UUID().uuidString)"
        let storage = UserDefaultStorage<Value>(
            key: key,
            suite: suiteName,
            defaultValue: defaultValue
        )
        let cleanup = {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        return (storage, cleanup)
    }

    // MARK: - Basic round trips

    @Test func defaultIsReturnedWhenKeyAbsent() {
        let (storage, cleanup) = makeStorage(defaultValue: "default")
        defer { cleanup() }
        #expect(storage.get() == "default")
    }

    @Test func stringRoundTrip() {
        let (storage, cleanup) = makeStorage(defaultValue: "default")
        defer { cleanup() }

        storage.set("hello")
        #expect(storage.get() == "hello")

        storage.set("world")
        #expect(storage.get() == "world")
    }

    @Test func intRoundTrip() {
        let (storage, cleanup) = makeStorage(defaultValue: 0)
        defer { cleanup() }

        storage.set(42)
        #expect(storage.get() == 42)
    }

    @Test func boolRoundTrip() {
        let (storage, cleanup) = makeStorage(defaultValue: false)
        defer { cleanup() }

        storage.set(true)
        #expect(storage.get() == true)
        storage.set(false)
        #expect(storage.get() == false)
    }

    @Test func dateRoundTrip() {
        let value = Date(timeIntervalSinceReferenceDate: 1_234_567.89)
        let (storage, cleanup) = makeStorage(defaultValue: Date(timeIntervalSinceReferenceDate: 0))
        defer { cleanup() }

        storage.set(value)
        #expect(storage.get() == value)
    }

    @Test func urlRoundTrip() {
        let value = URL(string: "https://example.com/path?q=1")!
        let fallback = URL(string: "https://default.example.com")!
        let (storage, cleanup) = makeStorage(defaultValue: fallback)
        defer { cleanup() }

        storage.set(value)
        #expect(storage.get() == value)
        // The underlying store sees the absolute string so plist editors stay
        // useful.
        #expect(storage.underlyingStore.string(forKey: "value") == value.absoluteString)
    }

    // MARK: - Optional / removal

    @Test func optionalNilRemovesKey() {
        let (storage, cleanup) = makeStorage(defaultValue: Optional<String>.some("initial"))
        defer { cleanup() }

        storage.set("active")
        #expect(storage.get() == "active")

        storage.set(nil)
        #expect(storage.get() == nil)
        #expect(storage.underlyingStore.object(forKey: "value") == nil)
    }

    // MARK: - Publisher

    @Test func publisherEmitsExactlyOnceOnLocalSet() async throws {
        let (storage, cleanup) = makeStorage(defaultValue: 0)
        defer { cleanup() }

        let received = ReceivedValues<Int>()
        let cancellable = storage.publisher.sink { received.append($0) }

        storage.set(1)
        storage.set(2)
        storage.set(3)

        // didChangeNotification is delivered synchronously inside set(); the
        // suppression flag should prevent any duplicate sends. Give the
        // runloop a tick in case anything is queued.
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.values == [1, 2, 3])
        cancellable.cancel()
    }

    @Test func publisherEmitsOnExternalWrite() async throws {
        let (storage, cleanup) = makeStorage(defaultValue: 0)
        defer { cleanup() }

        let received = ReceivedValues<Int>()
        let cancellable = storage.publisher.sink { received.append($0) }

        storage.underlyingStore.set(100, forKey: "value")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.values == [100])
        // The cache picked up the external value too.
        #expect(storage.get() == 100)
        cancellable.cancel()
    }

    @Test func publisherEmitsDefaultOnExternalRemove() async throws {
        let (storage, cleanup) = makeStorage(defaultValue: "default")
        defer { cleanup() }

        storage.set("active")
        let received = ReceivedValues<String>()
        let cancellable = storage.publisher.sink { received.append($0) }

        storage.underlyingStore.removeObject(forKey: "value")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.values == ["default"])
        #expect(storage.get() == "default")
        cancellable.cancel()
    }

    // MARK: - Error reporting

    @Test func errorHandlerCapturesDecodeFailure() {
        let suiteName = "com.frameworktoolbox.test.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let store = UserDefaults(suiteName: suiteName)!
        // Pre-seed an incompatible value so the first read mis-decodes.
        store.set("not-an-int", forKey: "value")

        let storage = UserDefaultStorage<Int>(key: "value", suite: suiteName, defaultValue: -1)

        let captured = ReceivedValues<UserDefaultError>()
        storage.errorHandler = { error in
            if let casted = error as? UserDefaultError {
                captured.append(casted)
            }
        }

        #expect(storage.get() == -1)
        #expect(captured.values.contains(.decodingFailed))
    }

    // MARK: - Concurrency

    /// Spins up two writers and a third agent that pokes the underlying
    /// store directly. The test passes if the run does not deadlock and the
    /// final cached value matches the final stored value, and the publisher
    /// never emits a value outside the union of writers' value spaces.
    @Test func concurrentSetIsConsistent() async throws {
        let (storage, cleanup) = makeStorage(defaultValue: -1)
        defer { cleanup() }

        let writerASpace = 0..<200
        let writerBSpace = 1000..<1200
        let externalSpace = 5000..<5050
        let allValues = Set(writerASpace)
            .union(Set(writerBSpace))
            .union(Set(externalSpace))
            .union(Set([-1]))

        let received = ReceivedValues<Int>()
        let cancellable = storage.publisher.sink { received.append($0) }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for value in writerASpace {
                    storage.set(value)
                }
            }
            group.addTask {
                for value in writerBSpace {
                    storage.set(value)
                }
            }
            group.addTask {
                for value in externalSpace {
                    storage.underlyingStore.set(value, forKey: "value")
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        cancellable.cancel()

        let finalCached = storage.get()
        let finalStored = storage.underlyingStore.integer(forKey: "value")
        #expect(finalCached == finalStored)

        for value in received.values {
            #expect(allValues.contains(value), "Publisher emitted unexpected value \(value)")
        }
    }

    // MARK: - Initialization-time errors

    @Test func suiteResolutionErrorFlowsToInitHandler() {
        let captured = ReceivedValues<UserDefaultError>()
        // "NSGlobalDomain" is a reserved name that UserDefaults(suiteName:)
        // refuses; the storage falls back to .standard and reports via the
        // init-supplied handler.
        let storage = UserDefaultStorage<String>(
            key: "value",
            suite: "NSGlobalDomain",
            defaultValue: "default",
            errorHandler: { error in
                if let casted = error as? UserDefaultError {
                    captured.append(casted)
                }
            }
        )
        #expect(storage.underlyingStore === UserDefaults.standard)
        #expect(captured.values.contains { error in
            if case .unresolvedSuite("NSGlobalDomain") = error { return true }
            return false
        })
    }

    // MARK: - Codable

    struct UserPreferences: PlistCodableStorable, Equatable {
        var theme: String
        var notificationsEnabled: Bool
    }

    @Test func codableRoundTrip() {
        let initial = UserPreferences(theme: "system", notificationsEnabled: false)
        let (storage, cleanup) = makeStorage(defaultValue: initial)
        defer { cleanup() }

        let updated = UserPreferences(theme: "dark", notificationsEnabled: true)
        storage.set(updated)
        #expect(storage.get() == updated)
    }
}

// MARK: - Test helper

private final class ReceivedValues<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var values: [Element] {
        lock.withLock { storage }
    }

    func append(_ value: Element) {
        lock.withLock { storage.append(value) }
    }
}
