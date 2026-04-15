import Foundation

/// A freestanding macro that wraps a string literal into a `Selector` value
/// without triggering the `Selector(String)` initializer warning.
///
/// Use this when you need to reference a selector whose method is not visible
/// to the Swift compiler (for example, a private or dynamically added method).
/// When the method *is* visible, prefer the built-in `#selector`, which
/// performs full compile-time validation against the real declaration.
///
/// Creating a `Selector` from a string literal like this
///
///     let selector = #Selector("tableView:didSelectRowAtIndexPath:")
///
/// results in the following code automatically
///
///     NSSelectorFromString("tableView:didSelectRowAtIndexPath:")
///
/// The macro performs a lenient compile-time check: the argument must be a
/// single-segment string literal that is non-empty and contains no whitespace.
/// It does **not** validate that the string is a syntactically legal
/// Objective-C method name.
@freestanding(expression)
public macro Selector(_ name: StaticString) -> Selector = #externalMacro(
    module: "FoundationToolboxMacros",
    type: "SelectorMacro"
)
