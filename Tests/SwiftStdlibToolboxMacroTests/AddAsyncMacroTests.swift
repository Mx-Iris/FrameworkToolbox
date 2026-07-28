import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "AddAsync": AddAsyncMacro.self,
    "AddAsyncAllMembers": AddAsyncAllMembersMacro.self,
]))
struct AddAsyncMacroTests {

    @Test func plainCompletionHandler() {
        assertMacro {
            """
            @AddAsync
            func fetchValue(completionHandler: @escaping (Int) -> Void) {
                completionHandler(42)
            }
            """
        } expansion: {
            """
            func fetchValue(completionHandler: @escaping (Int) -> Void) {
                completionHandler(42)
            }

            func fetchValue() async -> Int {
                await withCheckedContinuation { continuation in
                    fetchValue() { returnValue in
                        continuation.resume(returning: returnValue)
                    }
                }
            }
            """
        }
    }

    @Test func resultCompletionHandlerBecomesThrowing() {
        assertMacro {
            """
            @AddAsync
            func loadData(from url: URL, completionHandler: @escaping (Result<Data, Error>) -> Void) {
                completionHandler(.success(Data()))
            }
            """
        } expansion: {
            """
            func loadData(from url: URL, completionHandler: @escaping (Result<Data, Error>) -> Void) {
                completionHandler(.success(Data()))
            }

            func loadData(from url: URL) async throws -> Data {
                try await withCheckedThrowingContinuation { continuation in
                    loadData(from: url) { returnValue in
                        switch returnValue {
                            case .success(let value):
                                continuation.resume(returning: value)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                        }
                    }
                }
            }
            """
        }
    }

    @Test func parameterLabelsArePassedThrough() {
        assertMacro {
            """
            @AddAsync
            func request(_ path: String, method httpMethod: String, completion: @escaping (Result<String, Error>) -> Void) {
                completion(.success(path))
            }
            """
        } expansion: {
            """
            func request(_ path: String, method httpMethod: String, completion: @escaping (Result<String, Error>) -> Void) {
                completion(.success(path))
            }

            func request(_ path: String, method httpMethod: String) async throws -> String {
                try await withCheckedThrowingContinuation { continuation in
                    request(path, method: httpMethod) { returnValue in
                        switch returnValue {
                            case .success(let value):
                                continuation.resume(returning: value)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                        }
                    }
                }
            }
            """
        }
    }

    @Test func requirementWithoutBodyKeepsNoBody() {
        assertMacro {
            """
            protocol Loader {
                @AddAsync
                func load(completion: @escaping (Int) -> Void)
            }
            """
        } expansion: {
            """
            protocol Loader {
                func load(completion: @escaping (Int) -> Void)

                func load() async -> Int
            }
            """
        }
    }

    @Test func rejectsAlreadyAsyncFunction() {
        assertMacro {
            """
            @AddAsync
            func fetchValue(completionHandler: @escaping (Int) -> Void) async {
                completionHandler(42)
            }
            """
        } diagnostics: {
            """
            @AddAsync
            ┬────────
            ╰─ 🛑 @AddAsync requires a non async function
            func fetchValue(completionHandler: @escaping (Int) -> Void) async {
                completionHandler(42)
            }
            """
        }
    }

    @Test func rejectsNonVoidReturningFunction() {
        assertMacro {
            """
            @AddAsync
            func fetchValue(completionHandler: @escaping (Int) -> Void) -> Bool {
                completionHandler(42)
                return true
            }
            """
        } diagnostics: {
            """
            @AddAsync
            ┬────────
            ╰─ 🛑 @AddAsync requires a function that returns void
            func fetchValue(completionHandler: @escaping (Int) -> Void) -> Bool {
                completionHandler(42)
                return true
            }
            """
        }
    }

    @Test func rejectsMissingCompletionHandler() {
        assertMacro {
            """
            @AddAsync
            func fetchValue(count: Int) {
            }
            """
        } diagnostics: {
            """
            @AddAsync
            ┬────────
            ╰─ 🛑 @AddAsync requires a function that has a completion handler as last parameter
            func fetchValue(count: Int) {
            }
            """
        }
    }

    @Test func rejectsCompletionHandlerReturningNonVoid() {
        assertMacro {
            """
            @AddAsync
            func fetchValue(completionHandler: @escaping (Int) -> Bool) {
            }
            """
        } diagnostics: {
            """
            @AddAsync
            ┬────────
            ╰─ 🛑 @AddAsync requires a function that has a completion handler that returns Void
            func fetchValue(completionHandler: @escaping (Int) -> Bool) {
            }
            """
        }
    }

    @Test func rejectsCompletionHandlerWithoutParameter() {
        assertMacro {
            """
            @AddAsync
            func fetchValue(completionHandler: @escaping () -> Void) {
            }
            """
        } diagnostics: {
            """
            @AddAsync
            ┬────────
            ╰─ 🛑 @AddAsync requires a function that has a completion handler that has one parameter
            func fetchValue(completionHandler: @escaping () -> Void) {
            }
            """
        }
    }

    @Test func rejectsNonFunctionDeclaration() {
        assertMacro {
            """
            @AddAsync
            var value: Int = 0
            """
        } diagnostics: {
            """
            @AddAsync
            ┬────────
            ╰─ 🛑 @AddAsync only works on functions
            var value: Int = 0
            """
        }
    }

    @Test func allMembersSkipsIneligibleMembers() {
        assertMacro {
            """
            @AddAsyncAllMembers
            struct Client {
                func fetchValue(completionHandler: @escaping (Int) -> Void) {
                    completionHandler(42)
                }

                func loadData(completionHandler: @escaping (Result<Data, Error>) -> Void) {
                    completionHandler(.success(Data()))
                }

                func synchronousWork() -> Int {
                    0
                }

                var identifier: String = ""
            }
            """
        } expansion: {
            """
            struct Client {
                func fetchValue(completionHandler: @escaping (Int) -> Void) {
                    completionHandler(42)
                }

                func loadData(completionHandler: @escaping (Result<Data, Error>) -> Void) {
                    completionHandler(.success(Data()))
                }

                func synchronousWork() -> Int {
                    0
                }

                var identifier: String = ""

                func fetchValue() async -> Int {
                    await withCheckedContinuation { continuation in
                        fetchValue() { returnValue in
                            continuation.resume(returning: returnValue)
                        }
                    }
                }

                func loadData() async throws -> Data {
                    try await withCheckedThrowingContinuation { continuation in
                        loadData() { returnValue in
                            switch returnValue {
                                case .success(let value):
                                    continuation.resume(returning: value)
                                case .failure(let error):
                                    continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
            """
        }
    }
}
