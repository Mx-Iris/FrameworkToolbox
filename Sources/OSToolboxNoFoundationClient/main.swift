import OSToolbox

// This whole target is the guard: **no file in it may import Foundation.**
//
// A macro must not expand to code naming a module the caller has not imported,
// and the failure mode is nasty — the error lands on generated code the source
// never mentions. Two such defects have already shipped here (see
// `LoggableWithoutFoundation.swift`), and neither was caught by the earlier
// guard, which lived in `OSToolboxClient` alongside a `main.swift` that does
// `import Foundation`.
//
// That is the trap worth writing down: **Swift resolves protocol conformances
// module-wide, not per file.** One `import Foundation` anywhere in a target
// makes `String: CVarArg` visible to every file in it, however carefully an
// individual file avoids the import. A guard against accidental Foundation
// dependencies is therefore only a guard if it has a target to itself.

ServiceWithoutFoundation().emit()
ClassWithoutFoundation().emit()

let interpolating = InterpolatingServiceWithoutFoundation()
interpolating.emitSingleSegment(count: 1)
interpolating.emitSeveralSegments(name: "guard", count: 2, ratio: 0.5)
interpolating.emitMixedPrivacy(token: "secret", identifier: 3)
interpolating.emitEscapedPercent(percentage: 42)
interpolating.emitUnderACategory(count: 4)

DualAnnotatedService().emit()

// Run every signpost form, so the guard covers emission and not just compilation.
let signpostGuard = SignpostGuardService()
signpostGuard.emitEvent()
signpostGuard.emitEventWithMessage(index: 7)
signpostGuard.emitEventUnderACategory()
signpostGuard.emitEventWithEverything(name: "guard", index: 8)
signpostGuard.beginAndEndSeparately(byteCount: 1024)
signpostGuard.beginAndEndWithoutMessages()
signpostGuard.beginAndEndUnderACategory()
signpostGuard.beginWithAnIdentifierDerivedFromAnObject(object: DualAnnotatedService.self as AnyObject)
print("scoped returning:", signpostGuard.scopedReturningValue())
signpostGuard.scopedReturningVoid()
print("scoped multi-statement:", signpostGuard.scopedMultipleStatements())
print("scoped throwing:", try signpostGuard.scopedThrowing(shouldFail: false))
print("scoped categorised:", signpostGuard.scopedUnderACategory())
print("scoped explicit id:", signpostGuard.scopedWithAnExplicitIdentifier())

// The throwing body must still close its interval when it throws — the end sits
// in a `defer`, and a leaked interval would show up in Instruments as an
// interval that never ends.
do {
    _ = try signpostGuard.scopedThrowing(shouldFail: true)
    print("unreachable: scopedThrowing was expected to throw")
} catch {
    print("scoped throwing threw as expected, interval still closed")
}
