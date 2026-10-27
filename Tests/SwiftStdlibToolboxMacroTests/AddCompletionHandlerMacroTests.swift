import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "AddCompletionHandler": AddCompletionHandlerMacro.self,
]))
struct AddCompletionHandlerMacroTests {

    @Test func asyncFunctionWithReturnValue() {
        assertMacro {
            """
            @AddCompletionHandler
            func fetchValue(for identifier: String) async throws -> Int {
                42
            }
            """
        } expansion: {
            """
            func fetchValue(for identifier: String) async throws -> Int {
                42
            }

            func fetchValue(for identifier: String, completion: @escaping (Swift.Result<Int, any Swift.Error>) -> Void) {
                _Concurrency.Task {
                    do {
                        let result = try await fetchValue(for: identifier)
                        completion(.success(result))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            """
        }
    }

    @Test func asyncFunctionReturningVoid() {
        assertMacro {
            """
            @AddCompletionHandler
            func refresh() async throws {
            }
            """
        } expansion: {
            """
            func refresh() async throws {
            }

            func refresh(completion: @escaping (Swift.Result<Void, any Swift.Error>) -> Void) {
                _Concurrency.Task {
                    do {
                        try await refresh()
                        completion(.success(()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            """
        }
    }

    @Test func parameterLabelsArePassedThrough() {
        assertMacro {
            """
            @AddCompletionHandler
            func request(_ path: String, method httpMethod: String) async -> String {
                path
            }
            """
        } expansion: {
            """
            func request(_ path: String, method httpMethod: String) async -> String {
                path
            }

            func request(_ path: String, method httpMethod: String, completion: @escaping (Swift.Result<String, any Swift.Error>) -> Void) {
                _Concurrency.Task {
                    do {
                        let result = try await request(path, method: httpMethod)
                        completion(.success(result))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            """
        }
    }

    @Test func diagnosesNonAsyncFunction() {
        assertMacro {
            """
            @AddCompletionHandler
            func fetchValue() -> Int {
                42
            }
            """
        } diagnostics: {
            """
            @AddCompletionHandler
            func fetchValue() -> Int {
            ┬───
            ╰─ 🛑 can only add a completion-handler variant to an 'async' function
               ✏️ add 'async'
                42
            }
            """
        } fixes: {
            """
            @AddCompletionHandler
            func fetchValue() async-> Int {
                42
            }
            """
        } expansion: {
            """
            func fetchValue() async-> Int {
                42
            }

            func fetchValue(completion: @escaping (Swift.Result<Int, any Swift.Error>) -> Void) {
                _Concurrency.Task {
                    do {
                        let result = try await fetchValue()
                        completion(.success(result))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            """
        }
    }

    @Test func rejectsNonFunctionDeclaration() {
        assertMacro {
            """
            @AddCompletionHandler
            var value: Int = 0
            """
        } diagnostics: {
            """
            @AddCompletionHandler
            ┬────────────────────
            ╰─ 🛑 @AddCompletionHandler only works on functions
            var value: Int = 0
            """
        }
    }

    // `@Sendable` is opt-in: it lets a `nonisolated` type compile in the Swift 6
    // language mode, and it costs every caller that writes the handler on the
    // main actor. Spelling the default out changes nothing.
    @Test func sendableHandlerWhenRequested() {
        assertMacro {
            """
            @AddCompletionHandler(sendable: true)
            func fetchValue() async throws -> Int {
                42
            }

            @AddCompletionHandler(sendable: false)
            func refresh() async throws {
            }
            """
        } expansion: {
            """
            func fetchValue() async throws -> Int {
                42
            }

            func fetchValue(completion: @escaping @Sendable (Swift.Result<Int, any Swift.Error>) -> Void) {
                _Concurrency.Task {
                    do {
                        let result = try await fetchValue()
                        completion(.success(result))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            func refresh() async throws {
            }

            func refresh(completion: @escaping (Swift.Result<Void, any Swift.Error>) -> Void) {
                _Concurrency.Task {
                    do {
                        try await refresh()
                        completion(.success(()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            """
        }
    }

    // Whether the handler is `@Sendable` is part of the generated signature, so
    // it has to be known while the macro expands: a variable is reported on the
    // argument itself. The harness records no expansion once there is an error.
    @Test func rejectsSendableThatIsNotALiteral() {
        assertMacro {
            """
            @AddCompletionHandler(sendable: prefersSendable)
            func fetchValue() async throws -> Int {
                42
            }
            """
        } diagnostics: {
            """
            @AddCompletionHandler(sendable: prefersSendable)
                                            ┬──────────────
                                            ╰─ 🛑 `sendable:` must be a boolean literal. Whether the completion handler is `@Sendable` is part of the generated signature, so it is decided while the macro expands — there is no runtime for a computed value to be evaluated in.
            func fetchValue() async throws -> Int {
                42
            }
            """
        }
    }
}
