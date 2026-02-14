import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros(["CaseCheckable": CaseCheckableMacro.self]))
struct CaseCheckableMacroTests {

    @Test func basicEnum() {
        assertMacro {
            """
            @CaseCheckable
            enum Status {
                case active
                case inactive
                case pending
            }
            """
        } expansion: {
            """
            enum Status {
                case active
                case inactive
                case pending

                var isActive: Bool {
                    switch self {
                    case .active:
                        return true
                    default:
                        return false
                    }
                }

                var isInactive: Bool {
                    switch self {
                    case .inactive:
                        return true
                    default:
                        return false
                    }
                }

                var isPending: Bool {
                    switch self {
                    case .pending:
                        return true
                    default:
                        return false
                    }
                }
            }
            """
        }
    }

    @Test func explicitAccessLevel() {
        assertMacro {
            """
            @CaseCheckable(.public)
            public enum Status {
                case active
                case inactive
            }
            """
        } expansion: {
            """
            public enum Status {
                case active
                case inactive

                public var isActive: Bool {
                    switch self {
                    case .active:
                        return true
                    default:
                        return false
                    }
                }

                public var isInactive: Bool {
                    switch self {
                    case .inactive:
                        return true
                    default:
                        return false
                    }
                }
            }
            """
        }
    }

    @Test func enumWithAssociatedValues() {
        assertMacro {
            """
            @CaseCheckable
            enum Result {
                case success(String)
                case failure(Error)
                case loading
            }
            """
        } expansion: {
            """
            enum Result {
                case success(String)
                case failure(Error)
                case loading

                var isSuccess: Bool {
                    switch self {
                    case .success:
                        return true
                    default:
                        return false
                    }
                }

                var isFailure: Bool {
                    switch self {
                    case .failure:
                        return true
                    default:
                        return false
                    }
                }

                var isLoading: Bool {
                    switch self {
                    case .loading:
                        return true
                    default:
                        return false
                    }
                }
            }
            """
        }
    }
}
