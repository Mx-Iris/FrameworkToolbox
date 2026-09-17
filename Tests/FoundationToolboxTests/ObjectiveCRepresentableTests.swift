import Foundation
import Testing

import FoundationToolbox

// A deliberately un-collection-like conformer: it stores no Objective-C object, builds a
// representation on the way out and parses one on the way back. If the macro or the protocol
// had collection assumptions left in them, this would not compile — which is the point of
// testing with it rather than with another handle.
//
// No `typealias ObjectiveCRepresentation` here on purpose: `makeObjectiveCRepresentation()`
// is a direct witness, so the compiler infers it. (The collection handles must spell it out,
// because their conversion members come from a protocol extension, and a generic default
// implementation offers nothing to infer from.)
@ObjectiveCBridgeable
struct SemanticVersion: ObjectiveCRepresentable, Equatable {
    var major: Int
    var minor: Int

    func makeObjectiveCRepresentation() -> NSString {
        "\(major).\(minor)" as NSString
    }

    init?(objectiveCRepresentation source: NSString) {
        let components = (source as String).split(separator: ".")
        guard components.count == 2,
              let major = Int(components[0]),
              let minor = Int(components[1])
        else { return nil }
        self.major = major
        self.minor = minor
    }

    init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    static var substituteForMissingObjectiveCRepresentation: SemanticVersion {
        SemanticVersion(major: 0, minor: 0)
    }
}

@Suite("ObjectiveCRepresentable works for types that are not collections")
struct ObjectiveCRepresentableTests {

    @Test func valueReachingAnAnyObjectParameterBecomesItsObjectiveCRepresentation() {
        let version = SemanticVersion(major: 2, minor: 5)
        let bridged = version as AnyObject
        #expect(bridged is NSString)
        #expect(bridged as? String == "2.5")
    }

    @Test func conditionalBridgingParsesTheRepresentation() throws {
        let source: NSString = "3.1"
        let version = try #require(bridging(source, to: SemanticVersion.self))
        #expect(version == SemanticVersion(major: 3, minor: 1))
    }

    @Test func conditionalBridgingRejectsARepresentationThatDoesNotParse() {
        let source: NSString = "not a version"
        #expect(bridging(source, to: SemanticVersion.self) == nil)
    }

    // Unlike a collection handle, this type builds a representation instead of wrapping
    // one, so what survives the round trip is the value, not the object. Both shapes are
    // legitimate — the protocol imposes neither, which is the property being tested.
    //
    // Deliberately no `!==` assertion on the two representations: `"1.4" as NSString`
    // produces a tagged pointer, so two equal short strings really can be the same object.
    // That would be a test of NSString's internals, not of anything here.
    @Test func roundTripPreservesTheValue() throws {
        let original = SemanticVersion(major: 1, minor: 4)
        let representation = original as AnyObject
        let restored = try #require(bridging(representation, to: SemanticVersion.self))
        #expect(restored == original)
    }

    @Test func aTypeCanSupplyItsOwnSubstituteForAMissingRepresentation() {
        #expect(
            SemanticVersion._unconditionallyBridgeFromObjectiveC(nil)
                == SemanticVersion(major: 0, minor: 0)
        )
    }
}

/// Casts through `Any`, the same runtime path a call site's `as?` takes, without the
/// compiler's misleading `always succeeds` diagnostic on the literal spelling.
private func bridging<Value>(_ representation: Any, to valueType: Value.Type) -> Value? {
    representation as? Value
}
