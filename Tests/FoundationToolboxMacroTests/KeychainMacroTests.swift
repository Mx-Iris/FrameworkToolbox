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

            private let _accessToken = KeychainStorage<String>(
                key: "accessToken", service: "com.example.app",
                defaultValue: ""
            )

            var $accessToken: AnyPublisher<String, Never> {
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

            private let _launchCount = KeychainStorage<Int>(
                key: "launchCount", service: "com.example.app",
                defaultValue: 0
            )

            var $launchCount: AnyPublisher<Int, Never> {
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

            private let _refreshToken = KeychainStorage<String?>(
                key: "refreshToken", service: "com.example.app",
                defaultValue: nil
            )

            var $refreshToken: AnyPublisher<String?, Never> {
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

            private let _secret = KeychainStorage<String>(
                key: "secret", service: "com.example.app", synchronizable: false, accessible: .whenPasscodeSetThisDeviceOnly,
                defaultValue: ""
            )

            var $secret: AnyPublisher<String, Never> {
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

            private let _token = KeychainStorage<String>(
                key: "token", service: "com.example.app",
                defaultValue: ""
            )

            public var $token: AnyPublisher<String, Never> {
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

            private static let _shared = KeychainStorage<String>(
                key: "shared", service: "com.example.app",
                defaultValue: ""
            )

            static var $shared: AnyPublisher<String, Never> {
                _shared.publisher
            }
            """
        }
    }
}
