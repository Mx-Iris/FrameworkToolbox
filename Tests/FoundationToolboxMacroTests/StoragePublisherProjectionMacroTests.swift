import MacroTesting
import Testing

@testable import FoundationToolboxMacros

// The harness drops the initial value from its output. The compiler keeps it,
// for type inference only; `InferredStoragePropertyTests` and the client
// targets are what show that half.
@Suite(.macros(["_StoragePublisherProjection": StoragePublisherProjectionMacro.self]))
struct StoragePublisherProjectionMacroTests {
    // The getter reads the storage the projection's name points at, not the
    // initial value: that one only stands in for the type.
    @Test func readsTheStorageNamedAfterTheProjection() {
        assertMacro {
            """
            @_StoragePublisherProjection
            var $launchCount = FoundationToolbox.UserDefaultStorage(key: "launchCount", defaultValue: 0).publisher.eraseToAnyPublisher()
            """
        } expansion: {
            """
            var $launchCount {
                get {
                    _launchCount.publisher.eraseToAnyPublisher()
                }
            }
            """
        }
    }

    @Test func requiresAnInitializedProjection() {
        assertMacro {
            """
            @_StoragePublisherProjection
            var launchCount: Int
            """
        } diagnostics: {
            """
            @_StoragePublisherProjection
            ┬───────────────────────────
            ╰─ 🛑 '@_StoragePublisherProjection' must be applied to a single 'var $name' with an initial value
            var launchCount: Int
            """
        }
    }
}
