#if canImport(ObjectiveC)
import Foundation
import Testing
@testable import ObjCRuntimeToolbox

// `_ObjCTypeEncoding.of(_:)` is a set of overloads the compiler chooses between
// at each call site, so these calls exercise real overload resolution — the
// part a macro test cannot reach. Each group pins one way a type can match:
// a concrete overload, one constraint, two at once, or a stated encoding. The
// expected strings are what the Objective-C runtime reports for the C types.

private struct StatedEncoding: ObjCTypeEncodable {
    static var objCTypeEncoding: String { "{StatedEncoding=i}" }
}

private enum StatedRawEncoding: Int, ObjCTypeEncodable {
    case only
    static var objCTypeEncoding: String { "i" }
}

@Suite("Encodings the compiler works out for the runtime macros")
struct CompilerDerivedObjCTypeEncodingTests {
    @Test func typealiasesEncodeAsWhatTheyName() {
        #expect(_ObjCTypeEncoding.of(TimeInterval.self) == "d")
        #expect(_ObjCTypeEncoding.of(NSInteger.self) == "q")
        #expect(_ObjCTypeEncoding.of(pid_t.self) == "i")
        #expect(_ObjCTypeEncoding.of(CFTimeInterval.self) == "d")
    }

    @Test func concreteOverloadsWinOverBridging() {
        // Each of these is also `_ObjectiveCBridgeable`, which on its own would
        // say "object".
        #expect(_ObjCTypeEncoding.of(Int.self) == "q")
        #expect(_ObjCTypeEncoding.of(Bool.self) == "B")
        #expect(_ObjCTypeEncoding.of(Double.self) == "d")
        #expect(_ObjCTypeEncoding.of(CGFloat.self) == "d")
    }

    @Test func importedEnumerationsEncodeAsTheirRawValue() {
        #expect(_ObjCTypeEncoding.of(ComparisonResult.self) == "q")
        #expect(_ObjCTypeEncoding.of(NSString.CompareOptions.self) == "Q")
    }

    @Test func objectsAndBridgedValuesEncodeAsObjects() {
        #expect(_ObjCTypeEncoding.of(NSObject.self) == "@")
        #expect(_ObjCTypeEncoding.of(NSObjectProtocol.self) == "@")
        #expect(_ObjCTypeEncoding.of(String.self) == "@")
        #expect(_ObjCTypeEncoding.of([String].self) == "@")
    }

    @Test func aBridgingRawValueWrapperEncodesAsWhatCrosses() {
        // `RawRepresentable` and `_ObjectiveCBridgeable` at once; crosses as its
        // `NSString`.
        #expect(_ObjCTypeEncoding.of(NSNotification.Name.self) == "@")
    }

    @Test func structsOutsideTheMacrosTable() {
        #expect(_ObjCTypeEncoding.of(CGAffineTransform.self) == "{CGAffineTransform=dddddd}")
        #if os(macOS)
        #expect(_ObjCTypeEncoding.of(NSRect.self) == "{CGRect={CGPoint=dd}{CGSize=dd}}")
        #endif
    }

    @Test func aStatedEncodingWinsOverEveryRule() {
        #expect(_ObjCTypeEncoding.of(StatedEncoding.self) == "{StatedEncoding=i}")
        // Also `RawRepresentable`, which would otherwise say `q`.
        #expect(_ObjCTypeEncoding.of(StatedRawEncoding.self) == "i")
    }
}
#endif
