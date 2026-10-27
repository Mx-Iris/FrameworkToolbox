import SwiftStdlibToolbox

// A macro's expansion lands in the caller's scope, so every name it leaves
// unqualified resolves against whatever the caller has declared nearby. Apps
// routinely have a `Task` or a `Result` type of their own; the declarations
// below put such names right next to the generated code. They only have to
// compile.
enum ConcurrencyNameShadowingGuard {
    struct Task {}
    enum Result {}

    // Members shadow global functions of the same name, so these would capture
    // an unqualified call to the continuation functions.
    static func withCheckedContinuation() {}
    static func withCheckedThrowingContinuation() {}

    @AddCompletionHandler
    static func fetchValue() async throws -> Int {
        1
    }

    @AddAsync
    static func load(completion: @escaping (Int) -> Void) {
        completion(1)
    }

    @AddAsync
    static func loadResult(completion: @escaping (Swift.Result<Int, any Swift.Error>) -> Void) {
        completion(.success(1))
    }
}
