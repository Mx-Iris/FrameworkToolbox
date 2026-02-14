import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros(["AssociatedValue": AssociatedValueMacro.self]))
struct AssociatedValueMacroTests {

    @Test func basicEnum() {
        assertMacro {
            """
            @AssociatedValue
            enum State {
                case loading
                case loaded(User)
                case failed(Error)
            }
            """
        } expansion: {
            """
            enum State {
                case loading
                case loaded(User)
                case failed(Error)

                /// Returns the associated value of the `loaded` case if `self` is `.loaded`, otherwise returns `nil`.
                var loaded: User? {
                    switch self {
                    case .loaded(let loaded):
                        return loaded
                    default:
                        return nil
                    }
                }

                /// Returns the associated value of the `failed` case if `self` is `.failed`, otherwise returns `nil`.
                var failed: Error? {
                    switch self {
                    case .failed(let failed):
                        return failed
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }

    @Test func explicitAccessLevel() {
        assertMacro {
            """
            @AssociatedValue(.public)
            public enum State {
                case loaded(User)
                case failed(Error)
            }
            """
        } expansion: {
            """
            public enum State {
                case loaded(User)
                case failed(Error)

                /// Returns the associated value of the `loaded` case if `self` is `.loaded`, otherwise returns `nil`.
                public var loaded: User? {
                    switch self {
                    case .loaded(let loaded):
                        return loaded
                    default:
                        return nil
                    }
                }

                /// Returns the associated value of the `failed` case if `self` is `.failed`, otherwise returns `nil`.
                public var failed: Error? {
                    switch self {
                    case .failed(let failed):
                        return failed
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }

    @Test func withPrefix() {
        assertMacro {
            """
            @AssociatedValue(prefix: "get")
            enum State {
                case loaded(User)
            }
            """
        } expansion: {
            """
            enum State {
                case loaded(User)

                /// Returns the associated value of the `loaded` case if `self` is `.loaded`, otherwise returns `nil`.
                var getLoaded: User? {
                    switch self {
                    case .loaded(let loaded):
                        return loaded
                    }
                }
            }
            """
        }
    }

    @Test func withSuffix() {
        assertMacro {
            """
            @AssociatedValue(suffix: "Value")
            enum State {
                case loaded(User)
            }
            """
        } expansion: {
            """
            enum State {
                case loaded(User)

                /// Returns the associated value of the `loaded` case if `self` is `.loaded`, otherwise returns `nil`.
                var loadedValue: User? {
                    switch self {
                    case .loaded(let loaded):
                        return loaded
                    }
                }
            }
            """
        }
    }

    @Test func singleCase() {
        assertMacro {
            """
            @AssociatedValue
            enum Wrapper {
                case value(Int)
            }
            """
        } expansion: {
            """
            enum Wrapper {
                case value(Int)

                /// Returns the associated value of the `value` case if `self` is `.value`, otherwise returns `nil`.
                var value: Int? {
                    switch self {
                    case .value(let value):
                        return value
                    }
                }
            }
            """
        }
    }

    @Test func optionalAssociatedValue() {
        assertMacro {
            """
            @AssociatedValue
            enum State {
                case loaded(String?)
                case failed(Error)
            }
            """
        } expansion: {
            """
            enum State {
                case loaded(String?)
                case failed(Error)

                /// Returns the associated value of the `loaded` case if `self` is `.loaded`, otherwise returns `nil`.
                var loaded: String? {
                    switch self {
                    case .loaded(let loaded):
                        return loaded
                    default:
                        return nil
                    }
                }

                /// Returns the associated value of the `failed` case if `self` is `.failed`, otherwise returns `nil`.
                var failed: Error? {
                    switch self {
                    case .failed(let failed):
                        return failed
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }

    @Test func multipleTupleParametersSkipped() {
        assertMacro {
            """
            @AssociatedValue
            enum State {
                case loaded(User, Date)
                case simple(Int)
            }
            """
        } expansion: {
            """
            enum State {
                case loaded(User, Date)
                case simple(Int)

                /// Returns the associated value of the `simple` case if `self` is `.simple`, otherwise returns `nil`.
                var simple: Int? {
                    switch self {
                    case .simple(let simple):
                        return simple
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }
}
