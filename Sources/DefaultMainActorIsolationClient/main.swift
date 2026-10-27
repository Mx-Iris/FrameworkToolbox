// The macros expanded the way a new app target compiles them: Swift 6 language
// mode, `MainActor` as the default isolation (SE-0466), and the approachable
// concurrency features — see this target's settings in `Package.swift`.
//
// In such a module every declaration without an isolation of its own is
// main-actor isolated, generated ones included. A macro that drops the caller's
// `nonisolated`, or emits a member, a type or a conformance the caller cannot
// reach from a background thread, fails here and nowhere else: every other
// target in the package is Swift 5 with no default isolation. Everything below
// is used from a `nonisolated` function, so it only has to compile.
import FoundationToolbox

// MARK: - Enum macros on a type the caller took off the main actor

@CaseTag(backing: String.self)
@CaseCheckable
@AssociatedValue
nonisolated enum Payment {
    case card(String)
    case cash
}

nonisolated func describe(_ payment: Payment) -> String {
    let tag: PaymentTag = payment.tag
    let tags: Set<PaymentTag> = [tag, PaymentTag(rawValue: "cash") ?? .cash]
    return "\(tag.rawValue) \(tags.count) \(payment.isCard) \(payment.card ?? "")"
}

// MARK: - `@Equatable`, with and without the caller's own isolation

@Equatable
nonisolated struct Receipt: Hashable {
    let identifier: Int
    let total: Double
}

// Main-actor isolated, as everything is by default here. The `Equatable`
// conformance is the macro's, and it has to be usable from anywhere since its
// `==` is `nonisolated`. `Hashable` is the caller's own, and the caller takes it
// off the main actor the way the language provides.
@Equatable
struct Theme: nonisolated Hashable {
    let name: String
    @EquatableIgnored var cachedDescription: String = ""
}

@Equatable
struct Swatch {
    let hex: String
}

// `Hashable` only through a protocol that refines it, so the inheritance clause
// does not say so and the `hash(into:)` is chosen by overload resolution — once
// for a type taken off the main actor and once for one left on it. The second
// has to take the conformance off the main actor itself, macro or no macro:
// here a main-actor type conforming to a protocol that refines `Hashable` is
// rejected (`conformance … crosses into main actor-isolated code`) even with
// no `@Equatable` anywhere near it, while `Hashable` named directly is not.
protocol LedgerRecord: Hashable {}

@Equatable
nonisolated struct LedgerEntry: LedgerRecord {
    let identifier: Int
    @EquatableIgnored var memo: String = ""
}

@Equatable
struct Shelf: nonisolated LedgerRecord {
    let name: String
    @EquatableIgnored var label: String = ""
}

nonisolated func areEqual<Value: Equatable>(_ first: Value, _ second: Value) -> Bool {
    first == second
}

nonisolated func deduplicate(_ receipts: [Receipt], _ themes: [Theme], _ swatches: [Swatch]) -> Int {
    Set(receipts).count + Set(themes).count + (areEqual(swatches.first, swatches.last) ? 1 : 0)
}

nonisolated func distinctEntries(_ entries: [LedgerEntry]) -> Int {
    Set(entries).count
}

func distinctShelves(_ shelves: [Shelf]) -> Int {
    Set(shelves).count
}

// MARK: - `@ObjectiveCBridgeable` on a type the caller took off the main actor

@ObjectiveCBridgeable
nonisolated struct Identifier: ObjectiveCRepresentable {
    let rawValue: String

    func makeObjectiveCRepresentation() -> NSString {
        rawValue as NSString
    }

    init?(objectiveCRepresentation source: NSString) {
        rawValue = source as String
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated func bridge(_ identifier: Identifier) -> NSString {
    identifier as NSString
}

// MARK: - Storage macros

nonisolated final class Counter: Sendable {
    @Mutex
    var value: Int = 0
}

nonisolated final class Preferences: Sendable {
    @UserDefault(key: "default-isolation-guard.launchCount")
    var launchCount: Int = 0
}

nonisolated func touch(_ counter: Counter, _ preferences: Preferences) -> Int {
    counter.value += 1
    return counter.value + preferences.launchCount
}

// MARK: - `@AddCompletionHandler`, on and off the main actor

// The generated function hands the completion handler to a `Task`, which takes
// its closure as `sending`. On a `nonisolated` type nothing makes that handler
// safe to send unless it is `@Sendable`, so without `sendable: true` this
// expansion does not compile at all.
nonisolated struct ReceiptLoader {
    @AddCompletionHandler(sendable: true)
    func total(for identifier: Int) async throws -> Double {
        Double(identifier)
    }
}

nonisolated func loadTotal(with loader: ReceiptLoader) {
    loader.total(for: 1) { result in
        _ = try? result.get()
    }
}

// Left on the main actor, as everything is by default here, the default keeps
// the handler a plain closure: the generated task inherits the main actor, and
// a handler written on the main actor may touch main-actor state, as it always
// could. With `sendable: true` the closure below would not compile — even in
// the Swift 5 language mode.
struct ReceiptStore {
    @AddCompletionHandler
    func count() async throws -> Int {
        0
    }
}

final class ReceiptScreen {
    var summary = ""

    func reload(from store: ReceiptStore) {
        store.count { result in
            self.summary = "\(result)"
        }
    }
}

// MARK: - Logging from a background thread inside a main-actor type

@Loggable
@Signpostable
struct SyncService {
    nonisolated func run() {
        #log(.info, "running")
        #signpostInterval("run") {
            #signpost(.event, "tick")
        }
    }
}

nonisolated func runInBackground(_ service: SyncService) {
    service.run()
}

@Loggable
@Signpostable
protocol Networking {}

nonisolated struct NetworkClient: Networking {
    func send() {
        #log(.debug, "sending")
        #signpost(.event, "send")
    }
}

nonisolated func sendInBackground(_ client: NetworkClient) {
    client.send()
}

_ = describe(.cash)
_ = deduplicate([], [], [])
_ = distinctEntries([])
_ = distinctShelves([])
_ = bridge(Identifier(rawValue: "guard"))
