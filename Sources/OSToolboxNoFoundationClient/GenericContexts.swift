import OSToolbox

// Compile-time guard: `@Loggable` and `@Signpostable` must work inside a generic
// context. Swift forbids static stored properties in a generic type — including
// in a *non-generic* type nested inside one — so the macros generate their
// caches differently there, resolving each handle through the metatype-keyed
// runtime cache instead of a `static let`.
//
// Before that, the only way to log from a generic type was to declare a protocol,
// annotate the protocol, and conform. Nothing but compilation can catch a
// regression here, which is why these cases live in a client target rather than
// in a unit test.
//
// This target is also the no-Foundation guard (see `main.swift`), so these cases
// pin the second half of the same claim: the generic branch's expansion does not
// reach for Foundation either.

// MARK: - The type itself is generic

@Loggable
struct GenericBox<Element> {
    let element: Element

    func emit() {
        #log(.debug, "generic struct logging, element count 1")
    }
}

@Loggable
@Signpostable
final class GenericCache<Key, Value> {
    private var storage: [String: Value] = [:]

    func emit() {
        #log(.debug, "generic class logging under both macros")
        #signpost(.event, "generic-class-event")
    }

    func measure() -> Int {
        #signpostInterval("generic-class-interval") {
            storage.count
        }
    }
}

@Loggable
enum GenericOutcome<Success, Failure> {
    case succeeded(Success)
    case failed(Failure)

    func emit() {
        #log(.info, "generic enum logging")
    }
}

@Loggable
actor GenericCoordinator<Element> {
    func emit() {
        #log(.debug, "generic actor logging")
    }
}

// Several generic parameters plus a constraint clause — the detection keys off
// the presence of a generic parameter list, not its shape.
@Loggable
struct ConstrainedGenericStore<Element: Hashable, Metadata> where Metadata: Sendable {
    func emit() {
        #log(.debug, "constrained generic struct logging")
    }
}

// MARK: - Non-generic, but nested inside a generic type

// This is the case the declaration's own syntax tree cannot show: `Inner` has no
// generic parameters, yet `static let` is just as illegal inside it. The macro
// has to read `MacroExpansionContext.lexicalContext` to see the enclosing type.

struct OuterGenericContainer<Element> {
    @Loggable
    struct NestedNonGenericService {
        func emit() {
            #log(.debug, "non-generic type nested in a generic one")
        }
    }

    @Loggable
    @Signpostable
    final class NestedDualAnnotated {
        func emit() {
            #log(.debug, "nested dual-annotated type")
            #signpost(.event, "nested-dual-event")
        }
    }

    // Two levels down, to confirm the search walks the whole enclosing chain
    // rather than only the immediate parent.
    enum NestedNamespace {
        @Loggable
        struct DeeplyNestedService {
            func emit() {
                #log(.debug, "type nested two levels inside a generic one")
            }
        }
    }
}

// MARK: - Nested inside an extension

// `extension Box` says nothing about whether `Box` is generic, so the macro
// treats any enclosing extension as restricting. That is the safe direction: a
// needless runtime cache lookup costs nanoseconds, a wrongly emitted
// `static let` costs a compile error in the caller's file.

extension OuterGenericContainer {
    @Loggable
    struct ServiceInsideGenericExtension {
        func emit() {
            #log(.debug, "type declared in an extension of a generic type")
        }
    }
}

struct OuterNonGenericContainer {}

extension OuterNonGenericContainer {
    @Loggable
    struct ServiceInsideNonGenericExtension {
        func emit() {
            #log(.debug, "type declared in an extension of a non-generic type")
        }
    }
}
