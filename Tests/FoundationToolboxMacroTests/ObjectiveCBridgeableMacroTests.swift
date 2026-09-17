import MacroTesting
import Testing

@testable import FoundationToolboxMacros

@Suite(.macros(["ObjectiveCBridgeable": ObjectiveCBridgeableMacro.self]))
struct ObjectiveCBridgeableMacroTests {

    // The two `@_semantics` strings and `@_effects(readonly)` are the entire reason this is
    // a macro rather than a protocol extension: the round-trip elimination needs both halves
    // annotated *and* the witnesses on the concrete type. Dropping one is silent — the build
    // stays green and the optimization goes to zero — so the expansion is pinned literally.
    @Test func generatesWitnessesThatForwardToTheProtocol() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public struct Coordinate: ObjectiveCRepresentable {
                public var latitude: Double
            }
            """
        } expansion: {
            """
            public struct Coordinate: ObjectiveCRepresentable {
                public var latitude: Double
            }

            extension Coordinate: _ObjectiveCBridgeable {
                public typealias _ObjectiveCType = ObjectiveCRepresentation

                // Paired with `bridgeFromObjectiveC` below; the optimizer eliminates a round
                // trip only when it recognises both halves.
                @_semantics("convertToObjectiveC")
                public func _bridgeToObjectiveC() -> ObjectiveCRepresentation {
                    makeObjectiveCRepresentation()
                }

                public static func _forceBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) {
                    result = Self(uncheckedObjectiveCRepresentation: source)
                }

                @discardableResult
                public static func _conditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) -> Bool {
                    guard let value = Self(objectiveCRepresentation: source) else {
                        result = nil
                        return false
                    }
                    result = value
                    return true
                }

                @_semantics("bridgeFromObjectiveC")
                // `@_effects` blocks inlining unconditionally — the inliner bails on
                // `hasEffectsKind()` before it looks at anything else — so `inlinable:`
                // does not reach this one. Kept because the effects information is still
                // what lets the optimizer reason about the call it does emit.
                @_effects(readonly)
                public static func _unconditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation?
                ) -> Self {
                    guard let source else {
                        return Self.substituteForMissingObjectiveCRepresentation
                    }
                    return Self(uncheckedObjectiveCRepresentation: source)
                }
            }
            """
        }
    }

    // Nothing about the expansion depends on the attached type's shape: no stored property is
    // read, and the Objective-C class is never named — `_ObjectiveCType` is spelled as the
    // protocol's associated type and resolved in the concrete type's context.
    @Test func namesNoObjectiveCClassAndReadsNoStoredProperty() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public struct WrapsNothing: ObjectiveCRepresentable {
            }
            """
        } expansion: {
            """
            public struct WrapsNothing: ObjectiveCRepresentable {
            }

            extension WrapsNothing: _ObjectiveCBridgeable {
                public typealias _ObjectiveCType = ObjectiveCRepresentation

                // Paired with `bridgeFromObjectiveC` below; the optimizer eliminates a round
                // trip only when it recognises both halves.
                @_semantics("convertToObjectiveC")
                public func _bridgeToObjectiveC() -> ObjectiveCRepresentation {
                    makeObjectiveCRepresentation()
                }

                public static func _forceBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) {
                    result = Self(uncheckedObjectiveCRepresentation: source)
                }

                @discardableResult
                public static func _conditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) -> Bool {
                    guard let value = Self(objectiveCRepresentation: source) else {
                        result = nil
                        return false
                    }
                    result = value
                    return true
                }

                @_semantics("bridgeFromObjectiveC")
                // `@_effects` blocks inlining unconditionally — the inliner bails on
                // `hasEffectsKind()` before it looks at anything else — so `inlinable:`
                // does not reach this one. Kept because the effects information is still
                // what lets the optimizer reason about the call it does emit.
                @_effects(readonly)
                public static func _unconditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation?
                ) -> Self {
                    guard let source else {
                        return Self.substituteForMissingObjectiveCRepresentation
                    }
                    return Self(uncheckedObjectiveCRepresentation: source)
                }
            }
            """
        }
    }

    @Test func worksOnAnEnumSinceBridgingCoversEveryValueType() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public enum Direction: ObjectiveCRepresentable {
                case north
                case south
            }
            """
        } expansion: {
            """
            public enum Direction: ObjectiveCRepresentable {
                case north
                case south
            }

            extension Direction: _ObjectiveCBridgeable {
                public typealias _ObjectiveCType = ObjectiveCRepresentation

                // Paired with `bridgeFromObjectiveC` below; the optimizer eliminates a round
                // trip only when it recognises both halves.
                @_semantics("convertToObjectiveC")
                public func _bridgeToObjectiveC() -> ObjectiveCRepresentation {
                    makeObjectiveCRepresentation()
                }

                public static func _forceBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) {
                    result = Self(uncheckedObjectiveCRepresentation: source)
                }

                @discardableResult
                public static func _conditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) -> Bool {
                    guard let value = Self(objectiveCRepresentation: source) else {
                        result = nil
                        return false
                    }
                    result = value
                    return true
                }

                @_semantics("bridgeFromObjectiveC")
                // `@_effects` blocks inlining unconditionally — the inliner bails on
                // `hasEffectsKind()` before it looks at anything else — so `inlinable:`
                // does not reach this one. Kept because the effects information is still
                // what lets the optimizer reason about the call it does emit.
                @_effects(readonly)
                public static func _unconditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation?
                ) -> Self {
                    guard let source else {
                        return Self.substituteForMissingObjectiveCRepresentation
                    }
                    return Self(uncheckedObjectiveCRepresentation: source)
                }
            }
            """
        }
    }

    @Test func omitsTheAccessModifierForANonPublicType() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            struct InternalValue: ObjectiveCRepresentable {
            }
            """
        } expansion: {
            """
            struct InternalValue: ObjectiveCRepresentable {
            }

            extension InternalValue: _ObjectiveCBridgeable {
                typealias _ObjectiveCType = ObjectiveCRepresentation

                // Paired with `bridgeFromObjectiveC` below; the optimizer eliminates a round
                // trip only when it recognises both halves.
                @_semantics("convertToObjectiveC")
                func _bridgeToObjectiveC() -> ObjectiveCRepresentation {
                    makeObjectiveCRepresentation()
                }

                static func _forceBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) {
                    result = Self(uncheckedObjectiveCRepresentation: source)
                }

                @discardableResult
                static func _conditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) -> Bool {
                    guard let value = Self(objectiveCRepresentation: source) else {
                        result = nil
                        return false
                    }
                    result = value
                    return true
                }

                @_semantics("bridgeFromObjectiveC")
                // `@_effects` blocks inlining unconditionally — the inliner bails on
                // `hasEffectsKind()` before it looks at anything else — so `inlinable:`
                // does not reach this one. Kept because the effects information is still
                // what lets the optimizer reason about the call it does emit.
                @_effects(readonly)
                static func _unconditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation?
                ) -> Self {
                    guard let source else {
                        return Self.substituteForMissingObjectiveCRepresentation
                    }
                    return Self(uncheckedObjectiveCRepresentation: source)
                }
            }
            """
        }
    }

    @Test func rejectsAClassBecauseBridgingSkipsReferenceTypes() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public class ReferenceValue: ObjectiveCRepresentable {
            }
            """
        } diagnostics: {
            """
            @ObjectiveCBridgeable
            ┬────────────────────
            ╰─ 🛑 @ObjectiveCBridgeable can only be applied to a struct or an enum. `_ObjectiveCBridgeable` is only consulted for value types — a class is always bridged verbatim, so the conformance would never be used.
            public class ReferenceValue: ObjectiveCRepresentable {
            }
            """
        }
    }

    // `@inlinable` is opt-in because it turns the generated bodies into a compatibility
    // commitment — not something a macro should decide on a caller's behalf.
    @Test func emitsInlinableOnRequest() {
        assertMacro {
            """
            @ObjectiveCBridgeable(inlinable: true)
            public struct Coordinate: ObjectiveCRepresentable {
            }
            """
        } expansion: {
            """
            public struct Coordinate: ObjectiveCRepresentable {
            }

            extension Coordinate: _ObjectiveCBridgeable {
                public typealias _ObjectiveCType = ObjectiveCRepresentation

                // Paired with `bridgeFromObjectiveC` below; the optimizer eliminates a round
                // trip only when it recognises both halves.
                @inlinable
                @_semantics("convertToObjectiveC")
                public func _bridgeToObjectiveC() -> ObjectiveCRepresentation {
                    makeObjectiveCRepresentation()
                }

                @inlinable
                public static func _forceBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) {
                    result = Self(uncheckedObjectiveCRepresentation: source)
                }

                @inlinable
                @discardableResult
                public static func _conditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) -> Bool {
                    guard let value = Self(objectiveCRepresentation: source) else {
                        result = nil
                        return false
                    }
                    result = value
                    return true
                }

                @inlinable
                @_semantics("bridgeFromObjectiveC")
                // `@_effects` blocks inlining unconditionally — the inliner bails on
                // `hasEffectsKind()` before it looks at anything else — so `inlinable:`
                // does not reach this one. Kept because the effects information is still
                // what lets the optimizer reason about the call it does emit.
                @_effects(readonly)
                public static func _unconditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation?
                ) -> Self {
                    guard let source else {
                        return Self.substituteForMissingObjectiveCRepresentation
                    }
                    return Self(uncheckedObjectiveCRepresentation: source)
                }
            }
            """
        }
    }

    // `@inlinable` is an attribute, so the answer has to exist at expansion time. A computed
    // expression has no runtime to be evaluated in and is rejected rather than ignored.
    @Test func rejectsANonLiteralInlinableArgument() {
        assertMacro {
            """
            @ObjectiveCBridgeable(inlinable: shouldInline)
            public struct Coordinate: ObjectiveCRepresentable {
            }
            """
        } diagnostics: {
            """
            @ObjectiveCBridgeable(inlinable: shouldInline)
                                             ┬───────────
                                             ╰─ 🛑 `inlinable:` must be a boolean literal. `@inlinable` is an attribute, so whether to emit it is decided while the macro expands — there is no runtime for a computed value to be evaluated in.
            public struct Coordinate: ObjectiveCRepresentable {
            }
            """
        }
    }
}
