// `Synchronization` declares a `Mutex` of its own, so in a file that imports it
// next to this package a bare `Mutex` can be ambiguous. `@Mutex` used to expand
// to exactly that, with the error pointing at generated code the file never
// mentions. This file imports both on purpose and covers each storage shape the
// macro generates; it only has to compile.
import OSToolbox
import Synchronization

// The `@available` is what makes this a guard. Below macOS 15 the compiler drops
// `Synchronization.Mutex` as unavailable and the bare name resolves on its own,
// so the package's own deployment target hides the ambiguity; a caller whose
// target is macOS 15 or iOS 18 sees both declarations, which this reproduces.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class MutexBesideSynchronization: Sendable {
    @Mutex
    var count: Int = 0

    @Mutex
    var name: String!

    @Mutex
    weak var owner: AnyObject?
}
