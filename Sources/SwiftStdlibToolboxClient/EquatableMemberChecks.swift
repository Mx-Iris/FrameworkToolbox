import SwiftStdlibToolbox

// `@Equatable` asks the compiler whether each compared member conforms, by
// attaching a check whose overloads differ only in that constraint. Which one
// the compiler picks is decided here, by real overload resolution, which the
// macro tests cannot exercise: they map a macro name straight to one
// implementation. Every member below can be compared, each in a different way,
// so a check that picks the wrong overload — or one that should not be there —
// fails this file. It only has to compile.

struct MemberCheckPoint: Equatable {
    let x: Int
}

@Equatable
struct EquatableMemberCheckCoverage<Element: Equatable> {
    // Written with a type.
    let identifier: Int
    // Inferred from the initial value: a literal, then a conditional conformance.
    var label = "label"
    var points = [MemberCheckPoint]()
    // A generic parameter, constrained where the type declares it.
    let element: Element
    // Optional, and implicitly unwrapped, which is checked as the optional.
    let optionalPoint: MemberCheckPoint?
    var name: String!
    // Neither conforms, yet `==` compares both through standard library
    // overloads, so neither may be checked.
    let pair: (Int, String)
    let kind: Any.Type
}

@Equatable
struct HashableMemberCheckCoverage: Hashable {
    let identifier: Int
    var tags = Set<String>()
}

// `==` compares only the members declared directly in the type's body, but the
// compiler attaches member attributes inside an active `#if` clause as well. A
// check there would report a member that is never compared.
@Equatable
struct ConditionalMemberCheckCoverage {
    let identifier: Int
    #if DEBUG
    var debugCache: [String: Any] = [:]
    #endif
}
