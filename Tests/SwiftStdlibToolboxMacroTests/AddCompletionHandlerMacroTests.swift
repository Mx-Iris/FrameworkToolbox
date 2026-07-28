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

            func fetchValue(for identifier: String, completion: @escaping (Result<Int, Error>) -> Void) {
                Task {
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

            func refresh(completion: @escaping (Result<Void, Error>) -> Void) {
                Task {
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

            func request(_ path: String, method httpMethod: String, completion: @escaping (Result<String, Error>) -> Void) {
                Task {
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

            func fetchValue(completion: @escaping (Result<Int, Error>) -> Void) {
                Task {
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
}
