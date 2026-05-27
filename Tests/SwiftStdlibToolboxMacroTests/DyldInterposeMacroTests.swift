import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "DyldInterpose": DyldInterposeMacro.self,
]))
struct DyldInterposeMacroTests {

    @Test func simpleReplacement() {
        assertMacro {
            """
            @DyldInterpose(getpid)
            func myGetpid() -> pid_t {
                return 12345
            }
            """
        } expansion: {
            """
            func myGetpid() -> pid_t {
                return 12345
            }

            #if canImport(Darwin)
            #if compiler(>=6.3)
            @section("__DATA,__interpose")
            @used
            #else
            @_section("__DATA,__interpose")
            @_used
            #endif
            private let _dyldInterpose_myGetpid: (@convention(c) () -> pid_t, @convention(c) () -> pid_t) = (myGetpid, getpid)
            #endif
            """
        }
    }

    @Test func multipleParametersStripsLabels() {
        assertMacro {
            """
            @DyldInterpose(write)
            func myWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
                return write(fd, buffer, count)
            }
            """
        } expansion: {
            """
            func myWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
                return write(fd, buffer, count)
            }

            #if canImport(Darwin)
            #if compiler(>=6.3)
            @section("__DATA,__interpose")
            @used
            #else
            @_section("__DATA,__interpose")
            @_used
            #endif
            private let _dyldInterpose_myWrite: (@convention(c) (Int32, UnsafeRawPointer?, Int) -> Int, @convention(c) (Int32, UnsafeRawPointer?, Int) -> Int) = (myWrite, write)
            #endif
            """
        }
    }

    @Test func voidReturnDefaultsToVoid() {
        assertMacro {
            """
            @DyldInterpose(free)
            func myFree(_ pointer: UnsafeMutableRawPointer?) {
                free(pointer)
            }
            """
        } expansion: {
            """
            func myFree(_ pointer: UnsafeMutableRawPointer?) {
                free(pointer)
            }

            #if canImport(Darwin)
            #if compiler(>=6.3)
            @section("__DATA,__interpose")
            @used
            #else
            @_section("__DATA,__interpose")
            @_used
            #endif
            private let _dyldInterpose_myFree: (@convention(c) (UnsafeMutableRawPointer?) -> Void, @convention(c) (UnsafeMutableRawPointer?) -> Void) = (myFree, free)
            #endif
            """
        }
    }

    @Test func memberAccessTargetIsPreserved() {
        assertMacro {
            """
            @DyldInterpose(Darwin.getpid)
            func myGetpid() -> pid_t {
                return 0
            }
            """
        } expansion: {
            """
            func myGetpid() -> pid_t {
                return 0
            }

            #if canImport(Darwin)
            #if compiler(>=6.3)
            @section("__DATA,__interpose")
            @used
            #else
            @_section("__DATA,__interpose")
            @_used
            #endif
            private let _dyldInterpose_myGetpid: (@convention(c) () -> pid_t, @convention(c) () -> pid_t) = (myGetpid, Darwin.getpid)
            #endif
            """
        }
    }

    @Test func rejectsNonFunctionDeclaration() {
        assertMacro {
            """
            @DyldInterpose(getpid)
            var notAFunction: Int = 0
            """
        } diagnostics: {
            """
            @DyldInterpose(getpid)
            ┬─────────────────────
            ╰─ 🛑 @DyldInterpose can only be applied to a function declaration.
            var notAFunction: Int = 0
            """
        }
    }

    @Test func rejectsMissingTargetArgument() {
        assertMacro {
            """
            @DyldInterpose
            func myGetpid() -> pid_t {
                return 0
            }
            """
        } diagnostics: {
            """
            @DyldInterpose
            ┬─────────────
            ╰─ 🛑 @DyldInterpose requires the function being replaced as its first argument, e.g. @DyldInterpose(malloc).
            func myGetpid() -> pid_t {
                return 0
            }
            """
        }
    }

    @Test func rejectsThrowsFunction() {
        assertMacro {
            """
            @DyldInterpose(getpid)
            func myGetpid() throws -> pid_t {
                return 0
            }
            """
        } diagnostics: {
            """
            @DyldInterpose(getpid)
            ┬─────────────────────
            ╰─ 🛑 @DyldInterpose cannot be applied to a function marked `throws` because @convention(c) function types do not support effects.
            func myGetpid() throws -> pid_t {
                return 0
            }
            """
        }
    }

    @Test func rejectsAsyncFunction() {
        assertMacro {
            """
            @DyldInterpose(getpid)
            func myGetpid() async -> pid_t {
                return 0
            }
            """
        } diagnostics: {
            """
            @DyldInterpose(getpid)
            ┬─────────────────────
            ╰─ 🛑 @DyldInterpose cannot be applied to a function marked `async` because @convention(c) function types do not support effects.
            func myGetpid() async -> pid_t {
                return 0
            }
            """
        }
    }

    @Test func rejectsGenericFunction() {
        assertMacro {
            """
            @DyldInterpose(getpid)
            func myGetpid<T>() -> T {
                fatalError()
            }
            """
        } diagnostics: {
            """
            @DyldInterpose(getpid)
            ┬─────────────────────
            ╰─ 🛑 @DyldInterpose cannot be applied to a generic function because @convention(c) function types do not support generics.
            func myGetpid<T>() -> T {
                fatalError()
            }
            """
        }
    }

    @Test func rejectsInoutParameter() {
        assertMacro {
            """
            @DyldInterpose(someFunction)
            func myReplacement(_ value: inout Int32) {
            }
            """
        } diagnostics: {
            """
            @DyldInterpose(someFunction)
            ┬───────────────────────────
            ╰─ 🛑 @DyldInterpose cannot be applied to a function with `inout` parameters because @convention(c) function types do not support `inout`.
            func myReplacement(_ value: inout Int32) {
            }
            """
        }
    }
}
