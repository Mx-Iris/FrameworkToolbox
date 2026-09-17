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
}
