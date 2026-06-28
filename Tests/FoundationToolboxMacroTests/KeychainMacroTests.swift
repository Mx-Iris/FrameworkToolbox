import MacroTesting
import Testing

@testable import FoundationToolboxMacros

@Suite(.macros(["Keychain": KeychainMacro.self]))
struct KeychainMacroTests {

    @Test func stringProperty() {
        assertMacro {
            """
            @Keychain(key: "accessToken", service: "com.example.app")
            var accessToken: String = ""
            """
        } expansion: {
            """
            var accessToken: String {
                get {
                    _accessToken.get()
                }
                set {
                    _accessToken.set(newValue)
                }
            }

            private let _accessToken = FoundationToolbox.KeychainStorage<String>(
                key: "accessToken", service: "com.example.app",
                defaultValue: ""
            )

            var $accessToken: some Combine.Publisher<String, Never> {
                _accessToken.publisher
            }
            """
        }
    }

    @Test func intProperty() {
        assertMacro {
            """
            @Keychain(key: "launchCount", service: "com.example.app")
            var launchCount: Int = 0
            """
        } expansion: {
            """
            var launchCount: Int {
                get {
                    _launchCount.get()
                }
                set {
                    _launchCount.set(newValue)
                }
            }

            private let _launchCount = FoundationToolbox.KeychainStorage<Int>(
                key: "launchCount", service: "com.example.app",
                defaultValue: 0
            )

            var $launchCount: some Combine.Publisher<Int, Never> {
                _launchCount.publisher
            }
            """
        }
    }

    @Test func optionalProperty() {
        assertMacro {
            """
            @Keychain(key: "refreshToken", service: "com.example.app")
            var refreshToken: String? = nil
            """
        } expansion: {
            """
            var refreshToken: String? {
                get {
                    _refreshToken.get()
                }
                set {
                    _refreshToken.set(newValue)
                }
            }

            private let _refreshToken = FoundationToolbox.KeychainStorage<String?>(
                key: "refreshToken", service: "com.example.app",
                defaultValue: nil
            )

            var $refreshToken: some Combine.Publisher<String?, Never> {
                _refreshToken.publisher
            }
            """
        }
    }

    @Test func customAccessibility() {
        assertMacro {
            """
            @Keychain(key: "secret", service: "com.example.app", synchronizable: false, accessible: .whenPasscodeSetThisDeviceOnly)
            var secret: String = ""
            """
        } expansion: {
            """
            var secret: String {
                get {
                    _secret.get()
                }
                set {
                    _secret.set(newValue)
                }
            }

            private let _secret = FoundationToolbox.KeychainStorage<String>(
                key: "secret", service: "com.example.app", synchronizable: false, accessible: .whenPasscodeSetThisDeviceOnly,
                defaultValue: ""
            )

            var $secret: some Combine.Publisher<String, Never> {
                _secret.publisher
            }
            """
        }
    }

    @Test func publicProperty() {
        assertMacro {
            """
            @Keychain(key: "token", service: "com.example.app")
            public var token: String = ""
            """
        } expansion: {
            """
            public var token: String {
                get {
                    _token.get()
                }
                set {
                    _token.set(newValue)
                }
            }

            private let _token = FoundationToolbox.KeychainStorage<String>(
                key: "token", service: "com.example.app",
                defaultValue: ""
            )

            public var $token: some Combine.Publisher<String, Never> {
                _token.publisher
            }
            """
        }
    }

    @Test func staticProperty() {
        assertMacro {
            """
            @Keychain(key: "shared", service: "com.example.app")
            static var shared: String = ""
            """
        } expansion: {
            """
            static var shared: String {
                get {
                    _shared.get()
                }
                set {
                    _shared.set(newValue)
                }
            }

            private static let _shared = FoundationToolbox.KeychainStorage<String>(
                key: "shared", service: "com.example.app",
                defaultValue: ""
            )

            static var $shared: some Combine.Publisher<String, Never> {
                _shared.publisher
            }
            """
        }
    }

    // MARK: - Diagnostics

    @Test func rejectsLet() {
        // The diagnostic is emitted from both the AccessorMacro and PeerMacro
        // expansions, so it appears twice in the assertion.
        assertMacro {
            """
            @Keychain(key: "x", service: "s")
            let foo: String = ""
            """
        } diagnostics: {
            """
            @Keychain(key: "x", service: "s")
            ┬────────────────────────────────
            ├─ 🛑 @Keychain requires a `var` (settable) property; `let` is not supported.
            ╰─ 🛑 @Keychain requires a `var` (settable) property; `let` is not supported.
            let foo: String = ""
            """
        }
    }

    @Test func rejectsWeak() {
        assertMacro {
            """
            @Keychain(key: "x", service: "s")
            weak var foo: NSObject? = nil
            """
        } diagnostics: {
            """
            @Keychain(key: "x", service: "s")
            ┬────────────────────────────────
            ├─ 🛑 @Keychain cannot be applied to a `weak` property; the backing storage holds the value strongly.
            ╰─ 🛑 @Keychain cannot be applied to a `weak` property; the backing storage holds the value strongly.
            weak var foo: NSObject? = nil
            """
        }
    }

    @Test func privateSetProjectionKeepsReadAccess() {
        assertMacro {
            """
            @Keychain(key: "x", service: "s")
            public private(set) var foo: String = ""
            """
        } expansion: {
            """
            public private(set) var foo: String {
                get {
                    _foo.get()
                }
                set {
                    _foo.set(newValue)
                }
            }

            private let _foo = FoundationToolbox.KeychainStorage<String>(
                key: "x", service: "s",
                defaultValue: ""
            )

            public var $foo: some Combine.Publisher<String, Never> {
                _foo.publisher
            }
            """
        }
    }
}
