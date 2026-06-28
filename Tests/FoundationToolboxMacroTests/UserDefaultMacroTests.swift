import MacroTesting
import Testing

@testable import FoundationToolboxMacros

@Suite(.macros(["UserDefault": UserDefaultMacro.self]))
struct UserDefaultMacroTests {

    @Test func stringProperty() {
        assertMacro {
            """
            @UserDefault(key: "username")
            var username: String = ""
            """
        } expansion: {
            """
            var username: String {
                get {
                    _username.get()
                }
                set {
                    _username.set(newValue)
                }
            }

            private let _username = FoundationToolbox.UserDefaultStorage<String>(
                key: "username",
                defaultValue: ""
            )

            var $username: some Combine.Publisher<String, Never> {
                _username.publisher
            }
            """
        }
    }

    @Test func intProperty() {
        assertMacro {
            """
            @UserDefault(key: "launchCount")
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

            private let _launchCount = FoundationToolbox.UserDefaultStorage<Int>(
                key: "launchCount",
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
            @UserDefault(key: "refreshToken")
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

            private let _refreshToken = FoundationToolbox.UserDefaultStorage<String?>(
                key: "refreshToken",
                defaultValue: nil
            )

            var $refreshToken: some Combine.Publisher<String?, Never> {
                _refreshToken.publisher
            }
            """
        }
    }

    @Test func customSuite() {
        assertMacro {
            """
            @UserDefault(key: "shared", suite: "group.com.example")
            var shared: String = ""
            """
        } expansion: {
            """
            var shared: String {
                get {
                    _shared.get()
                }
                set {
                    _shared.set(newValue)
                }
            }

            private let _shared = FoundationToolbox.UserDefaultStorage<String>(
                key: "shared", suite: "group.com.example",
                defaultValue: ""
            )

            var $shared: some Combine.Publisher<String, Never> {
                _shared.publisher
            }
            """
        }
    }

    @Test func publicProperty() {
        assertMacro {
            """
            @UserDefault(key: "token")
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

            private let _token = FoundationToolbox.UserDefaultStorage<String>(
                key: "token",
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
            @UserDefault(key: "shared")
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

            private static let _shared = FoundationToolbox.UserDefaultStorage<String>(
                key: "shared",
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
            @UserDefault(key: "x")
            let foo: String = ""
            """
        } diagnostics: {
            """
            @UserDefault(key: "x")
            ┬─────────────────────
            ├─ 🛑 @UserDefault requires a `var` (settable) property; `let` is not supported.
            ╰─ 🛑 @UserDefault requires a `var` (settable) property; `let` is not supported.
            let foo: String = ""
            """
        }
    }

    @Test func rejectsWeak() {
        assertMacro {
            """
            @UserDefault(key: "x")
            weak var foo: NSObject? = nil
            """
        } diagnostics: {
            """
            @UserDefault(key: "x")
            ┬─────────────────────
            ├─ 🛑 @UserDefault cannot be applied to a `weak` property; the backing storage holds the value strongly.
            ╰─ 🛑 @UserDefault cannot be applied to a `weak` property; the backing storage holds the value strongly.
            weak var foo: NSObject? = nil
            """
        }
    }

    @Test func privateSetProjectionKeepsReadAccess() {
        assertMacro {
            """
            @UserDefault(key: "x")
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

            private let _foo = FoundationToolbox.UserDefaultStorage<String>(
                key: "x",
                defaultValue: ""
            )

            public var $foo: some Combine.Publisher<String, Never> {
                _foo.publisher
            }
            """
        }
    }
}
