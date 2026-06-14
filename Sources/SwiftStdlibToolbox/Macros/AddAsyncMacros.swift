/// Generates an `async` overload of a completion-handler based function.
///
/// Attach this attribute to a non-`async`, `Void`-returning function whose last
/// parameter is a completion handler. The macro emits a peer `async` function
/// that wraps the original call in a checked continuation. When the completion
/// handler delivers a `Result`, the generated overload is `async throws` and
/// resumes by returning the success value or throwing the failure; otherwise it
/// is `async` and resumes with the delivered value.
@attached(peer, names: overloaded)
public macro AddAsync() = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AddAsyncMacro"
)

/// Applies `@AddAsync` to every member of the attached type.
///
/// Attach this attribute to a type to generate `async` overloads for all of its
/// eligible completion-handler based member functions at once. Members that do
/// not satisfy `@AddAsync`'s requirements are skipped.
@attached(member, names: arbitrary)
public macro AddAsyncAllMembers() = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AddAsyncAllMembersMacro"
)

/// Generates a completion-handler based overload of an `async` function.
///
/// Attach this attribute to an `async` function to emit a peer function that
/// takes an `@escaping (Result<ReturnType, Error>) -> Void` completion handler.
/// The generated overload runs the original `async` call inside a `Task` and
/// forwards its result (or thrown error) to the completion handler.
@attached(peer, names: overloaded)
public macro AddCompletionHandler() = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AddCompletionHandlerMacro"
)
