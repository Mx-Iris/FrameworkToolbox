import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "DyldDynamicInterpose": DyldDynamicInterposeMacro.self,
]))
struct DyldDynamicInterposeMacroTests {

    @Test func simpleReplacement() {
        assertMacro {
            """
            @DyldDynamicInterpose(getpid)
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
            @section("__DATA,__dyn_interpose")
            @used
            #else
            @_section("__DATA,__dyn_interpose")
            @_used
            #endif
            private let _dyldDynamicInterpose_myGetpid: (@convention(c) () -> pid_t, @convention(c) () -> pid_t) = (myGetpid, getpid)
            #endif
            """
        }
    }

    @Test func multipleParametersStripsLabels() {
        assertMacro {
            """
            @DyldDynamicInterpose(write)
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
            @section("__DATA,__dyn_interpose")
            @used
            #else
            @_section("__DATA,__dyn_interpose")
            @_used
            #endif
            private let _dyldDynamicInterpose_myWrite: (@convention(c) (Int32, UnsafeRawPointer?, Int) -> Int, @convention(c) (Int32, UnsafeRawPointer?, Int) -> Int) = (myWrite, write)
            #endif
            """
        }
    }

    @Test func voidReturnDefaultsToVoid() {
        assertMacro {
            """
            @DyldDynamicInterpose(free)
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
            @section("__DATA,__dyn_interpose")
            @used
            #else
            @_section("__DATA,__dyn_interpose")
            @_used
            #endif
            private let _dyldDynamicInterpose_myFree: (@convention(c) (UnsafeMutableRawPointer?) -> Void, @convention(c) (UnsafeMutableRawPointer?) -> Void) = (myFree, free)
            #endif
            """
        }
    }

    @Test func memberAccessTargetIsPreserved() {
        assertMacro {
            """
            @DyldDynamicInterpose(Darwin.getpid)
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
            @section("__DATA,__dyn_interpose")
            @used
            #else
            @_section("__DATA,__dyn_interpose")
            @_used
            #endif
            private let _dyldDynamicInterpose_myGetpid: (@convention(c) () -> pid_t, @convention(c) () -> pid_t) = (myGetpid, Darwin.getpid)
            #endif
            """
        }
    }

    @Test func rejectsNonFunctionDeclaration() {
        assertMacro {
            """
            @DyldDynamicInterpose(getpid)
            var notAFunction: Int = 0
            """
        } diagnostics: {
            """
            @DyldDynamicInterpose(getpid)
            ┬────────────────────────────
            ╰─ 🛑 @DyldDynamicInterpose can only be applied to a function declaration.
            var notAFunction: Int = 0
            """
        }
    }

    @Test func rejectsMissingTargetArgument() {
        assertMacro {
            """
            @DyldDynamicInterpose
            func myGetpid() -> pid_t {
                return 0
            }
            """
        } diagnostics: {
            """
            @DyldDynamicInterpose
            ┬────────────────────
            ╰─ 🛑 @DyldDynamicInterpose requires the function being replaced as its first argument, e.g. @DyldDynamicInterpose(malloc).
            func myGetpid() -> pid_t {
                return 0
            }
            """
        }
    }

    @Test func rejectsThrowsFunction() {
        assertMacro {
            """
            @DyldDynamicInterpose(getpid)
            func myGetpid() throws -> pid_t {
                return 0
            }
            """
        } diagnostics: {
            """
            @DyldDynamicInterpose(getpid)
            ┬────────────────────────────
            ╰─ 🛑 @DyldDynamicInterpose cannot be applied to a function marked `throws` because @convention(c) function types do not support effects.
            func myGetpid() throws -> pid_t {
                return 0
            }
            """
        }
    }

    @Test func rejectsAsyncFunction() {
        assertMacro {
            """
            @DyldDynamicInterpose(getpid)
            func myGetpid() async -> pid_t {
                return 0
            }
            """
        } diagnostics: {
            """
            @DyldDynamicInterpose(getpid)
            ┬────────────────────────────
            ╰─ 🛑 @DyldDynamicInterpose cannot be applied to a function marked `async` because @convention(c) function types do not support effects.
            func myGetpid() async -> pid_t {
                return 0
            }
            """
        }
    }

    @Test func rejectsGenericFunction() {
        assertMacro {
            """
            @DyldDynamicInterpose(getpid)
            func myGetpid<T>() -> T {
                fatalError()
            }
            """
        } diagnostics: {
            """
            @DyldDynamicInterpose(getpid)
            ┬────────────────────────────
            ╰─ 🛑 @DyldDynamicInterpose cannot be applied to a generic function because @convention(c) function types do not support generics.
            func myGetpid<T>() -> T {
                fatalError()
            }
            """
        }
    }

    @Test func rejectsInoutParameter() {
        assertMacro {
            """
            @DyldDynamicInterpose(someFunction)
            func myReplacement(_ value: inout Int32) {
            }
            """
        } diagnostics: {
            """
            @DyldDynamicInterpose(someFunction)
            ┬──────────────────────────────────
            ╰─ 🛑 @DyldDynamicInterpose cannot be applied to a function with `inout` parameters because @convention(c) function types do not support `inout`.
            func myReplacement(_ value: inout Int32) {
            }
            """
        }
    }
}
