import FrameworkToolbox
import Foundation

// `@FrameworkToolboxExtension` emits a `box` setter that writes back for value
// types and stays empty for a class-bound protocol, whose extension setters are
// not `mutating` — assigning `self` there crashes the compiler rather than being
// diagnosed. The macro only sees the extension, never the protocol, so the
// compiler makes the choice, from whether `Self` is constrained to `AnyObject`.
// The protocols below need different choices, and none of them says which: a
// wrong choice on the class-bound ones crashes the compiler on this file, and on
// the value one silently drops every `mutating` call made through `.box`. It
// only has to compile; the write-back itself is covered by
// `ComparableExtensionTests`, through the macro's `BinaryInteger` extension.

protocol ClassBoundService: AnyObject {}

@FrameworkToolboxExtension(.internal)
extension ClassBoundService {}

@objc protocol ObjectiveCService {}

@FrameworkToolboxExtension(.internal)
extension ObjectiveCService {}

protocol ValueService {}

@FrameworkToolboxExtension(.internal)
extension ValueService {}
