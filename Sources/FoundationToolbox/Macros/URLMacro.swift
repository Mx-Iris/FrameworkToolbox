import Foundation

/// Source: https://github.com/davidsteppenbeck/URL

/// An freestanding macro that provides an unwrapped `Foundation URL` for the string literal argument.
/// The macro checks the validity of the literal and throws an error if it does not represent a valid `Foundation URL`.
///
/// Creating a `URL` from a string literal like this
///
///     let url = #URL("https://www.apple.com")
///
/// results in the following code automatically
///
///     URL(string: "https://www.apple.com")!
@freestanding(expression)
public macro URL(_ str: StaticString) -> URL = #externalMacro(module: "FoundationToolboxMacros", type: "URLMacro")
