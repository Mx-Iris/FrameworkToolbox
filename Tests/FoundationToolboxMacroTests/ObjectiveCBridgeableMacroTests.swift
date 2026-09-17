import MacroTesting
import Testing

@testable import FoundationToolboxMacros

@Suite(.macros(["ObjectiveCBridgeable": ObjectiveCBridgeableMacro.self]))
struct ObjectiveCBridgeableMacroTests {

    // The two `@_semantics` strings and `@_effects(readonly)` are the entire reason this
    // macro exists rather than a protocol extension: the round-trip elimination needs both
    // halves annotated *and* the witnesses on the concrete type. Dropping one is silent, so
    // the expansion is pinned literally.
    @Test func generatesBridgingWitnessesOntoTheConcreteType() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public struct NSArrayOf<Element> {
                public let rawValue: NSArray
            }
            """
        } expansion: {
            """
            public struct NSArrayOf<Element> {
                public let rawValue: NSArray
            }

            extension NSArrayOf: _ObjectiveCBridgeable {
                public typealias _ObjectiveCType = NSArray

                // Paired with `bridgeFromObjectiveC` below; the optimizer's round-trip
                // elimination only fires when it recognises both halves.
                @_semantics("convertToObjectiveC")
                public func _bridgeToObjectiveC() -> NSArray {
                    rawValue
                }

                // This direction is allowed to defer element checking — it is what lets
                // `as!` skip the walk — so it does not validate.
                public static func _forceBridgeFromObjectiveC(
                    _ source: NSArray,
                    result: inout Self?
                ) {
                    result = Self(rawValue: source)
                }

                @discardableResult
                public static func _conditionallyBridgeFromObjectiveC(
                    _ source: NSArray,
                    result: inout Self?
                ) -> Bool {
                    guard Self.containsOnlyExpectedElementTypes(in: source) else {
                        result = nil
                        return false
                    }
                    result = Self(rawValue: source)
                    return true
                }

                @_semantics("bridgeFromObjectiveC")
                @_effects(readonly)
                public static func _unconditionallyBridgeFromObjectiveC(
                    _ source: NSArray?
                ) -> Self {
                    guard let source else {
                        return Self()
                    }
                    return Self(rawValue: source)
                }
            }
            """
        }
    }

    @Test func readsTheObjectiveCTypeFromRawValueAndKeepsEveryGenericParameter() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public struct NSMutableDictionaryOf<Key, Value> {
                public let rawValue: NSMutableDictionary
            }
            """
        } expansion: {
            """
            public struct NSMutableDictionaryOf<Key, Value> {
                public let rawValue: NSMutableDictionary
            }

            extension NSMutableDictionaryOf: _ObjectiveCBridgeable {
                public typealias _ObjectiveCType = NSMutableDictionary

                // Paired with `bridgeFromObjectiveC` below; the optimizer's round-trip
                // elimination only fires when it recognises both halves.
                @_semantics("convertToObjectiveC")
                public func _bridgeToObjectiveC() -> NSMutableDictionary {
                    rawValue
                }

                // This direction is allowed to defer element checking — it is what lets
                // `as!` skip the walk — so it does not validate.
                public static func _forceBridgeFromObjectiveC(
                    _ source: NSMutableDictionary,
                    result: inout Self?
                ) {
                    result = Self(rawValue: source)
                }

                @discardableResult
                public static func _conditionallyBridgeFromObjectiveC(
                    _ source: NSMutableDictionary,
                    result: inout Self?
                ) -> Bool {
                    guard Self.containsOnlyExpectedElementTypes(in: source) else {
                        result = nil
                        return false
                    }
                    result = Self(rawValue: source)
                    return true
                }

                @_semantics("bridgeFromObjectiveC")
                @_effects(readonly)
                public static func _unconditionallyBridgeFromObjectiveC(
                    _ source: NSMutableDictionary?
                ) -> Self {
                    guard let source else {
                        return Self()
                    }
                    return Self(rawValue: source)
                }
            }
            """
        }
    }

    @Test func omitsTheAccessModifierForANonPublicType() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            struct InternalHandle {
                let rawValue: NSArray
            }
            """
        } expansion: {
            """
            struct InternalHandle {
                let rawValue: NSArray
            }

            extension InternalHandle: _ObjectiveCBridgeable {
                typealias _ObjectiveCType = NSArray

                // Paired with `bridgeFromObjectiveC` below; the optimizer's round-trip
                // elimination only fires when it recognises both halves.
                @_semantics("convertToObjectiveC")
                func _bridgeToObjectiveC() -> NSArray {
                    rawValue
                }

                // This direction is allowed to defer element checking — it is what lets
                // `as!` skip the walk — so it does not validate.
                static func _forceBridgeFromObjectiveC(
                    _ source: NSArray,
                    result: inout Self?
                ) {
                    result = Self(rawValue: source)
                }

                @discardableResult
                static func _conditionallyBridgeFromObjectiveC(
                    _ source: NSArray,
                    result: inout Self?
                ) -> Bool {
                    guard Self.containsOnlyExpectedElementTypes(in: source) else {
                        result = nil
                        return false
                    }
                    result = Self(rawValue: source)
                    return true
                }

                @_semantics("bridgeFromObjectiveC")
                @_effects(readonly)
                static func _unconditionallyBridgeFromObjectiveC(
                    _ source: NSArray?
                ) -> Self {
                    guard let source else {
                        return Self()
                    }
                    return Self(rawValue: source)
                }
            }
            """
        }
    }

    @Test func rejectsAClassBecauseBridgingSkipsReferenceTypes() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public class ReferenceHandle {
                public let rawValue: NSArray = NSArray()
            }
            """
        } diagnostics: {
            """
            @ObjectiveCBridgeable
            ┬────────────────────
            ╰─ 🛑 @ObjectiveCBridgeable can only be applied to a struct. `_ObjectiveCBridgeable` is only consulted for value types — a class is always bridged verbatim, so the conformance would never be used.
            public class ReferenceHandle {
                public let rawValue: NSArray = NSArray()
            }
            """
        }
    }

    @Test func rejectsATypeWithNoRawValueToReadTheObjectiveCTypeFrom() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public struct WithoutRawValue {
                public let storage: NSArray
            }
            """
        } diagnostics: {
            """
            @ObjectiveCBridgeable
            ┬────────────────────
            ╰─ 🛑 @ObjectiveCBridgeable requires a stored `rawValue` property with an explicit type annotation naming the Objective-C class to bridge to, for example `let rawValue: NSArray`.
            public struct WithoutRawValue {
                public let storage: NSArray
            }
            """
        }
    }

    @Test func ignoresAComputedRawValueSinceTheBridgeNeedsStorage() {
        assertMacro {
            """
            @ObjectiveCBridgeable
            public struct ComputedRawValue {
                public var rawValue: NSArray { NSArray() }
            }
            """
        } diagnostics: {
            """
            @ObjectiveCBridgeable
            ┬────────────────────
            ╰─ 🛑 @ObjectiveCBridgeable requires a stored `rawValue` property with an explicit type annotation naming the Objective-C class to bridge to, for example `let rawValue: NSArray`.
            public struct ComputedRawValue {
                public var rawValue: NSArray { NSArray() }
            }
            """
        }
    }
}
