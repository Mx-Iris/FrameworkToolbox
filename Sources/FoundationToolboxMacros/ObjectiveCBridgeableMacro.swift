import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates the `_ObjectiveCBridgeable` witnesses for a type that conforms to
/// `ObjectiveCRepresentable`.
///
/// The macro makes no assumptions about the attached type beyond that conformance: it does
/// not read its properties, does not need to be told the Objective-C class, and generates
/// nothing but forwarding. Every witness delegates to an `ObjectiveCRepresentable` member,
/// and `_ObjectiveCType` is spelled as the protocol's own `ObjectiveCRepresentation`
/// associated type, which the compiler resolves in the concrete type's context. So the
/// conversion logic lives entirely in ordinary, non-underscored API that the author writes,
/// and the macro contributes exactly one thing: witnesses the optimizer can see through.
///
/// ## Why that one thing needs a macro
///
/// Those four methods forward, so writing them once as default implementations in a protocol
/// extension is the obvious move — and it costs the entire optimization. Measured by reading
/// optimized SIL of a bridge-to-Swift-and-straight-back round trip:
///
/// | Witness lives in | `@_semantics` | Round trip |
/// |---|---|---|
/// | protocol extension | present | **not** eliminated |
/// | concrete type | absent | **not** eliminated |
/// | concrete type | present | eliminated, down to `return %0` |
///
/// Both conditions are load-bearing. `objc-bridging-optimization` requires
/// `arguments.count == 2` with a `.directGuaranteed` first argument, and a witness in a
/// protocol extension has an opaque `Self` that must travel indirectly (`@out` one way,
/// `@in_guaranteed` the other), so the pass never matches it. Emitting onto the concrete
/// type fixes the calling convention; the `@_semantics` pair is what makes the pass
/// recognise the functions as bridging at all.
///
/// Neither condition reports anything when it breaks. Drop one underscored attribute and the
/// optimization silently returns to zero with the build still green — which is the whole
/// reason this is generated rather than copied by hand.
public struct ObjectiveCBridgeableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: ObjectiveCBridgeableMacroError.notAValueType))
            return []
        }

        let accessLevel = accessLevelPrefix(of: declaration)

        let extensionDeclaration = try ExtensionDeclSyntax(
            """
            extension \(type.trimmed): _ObjectiveCBridgeable {
                \(raw: accessLevel)typealias _ObjectiveCType = ObjectiveCRepresentation

                // Paired with `bridgeFromObjectiveC` below; the optimizer eliminates a round
                // trip only when it recognises both halves.
                @_semantics("convertToObjectiveC")
                \(raw: accessLevel)func _bridgeToObjectiveC() -> ObjectiveCRepresentation {
                    makeObjectiveCRepresentation()
                }

                \(raw: accessLevel)static func _forceBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation,
                    result: inout Self?
                ) {
                    result = Self(uncheckedObjectiveCRepresentation: source)
                }

                @discardableResult
                \(raw: accessLevel)static func _conditionallyBridgeFromObjectiveC(
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
                \(raw: accessLevel)static func _unconditionallyBridgeFromObjectiveC(
                    _ source: ObjectiveCRepresentation?
                ) -> Self {
                    guard let source else {
                        return Self.substituteForMissingObjectiveCRepresentation
                    }
                    return Self(uncheckedObjectiveCRepresentation: source)
                }
            }
            """
        )

        return [extensionDeclaration]
    }

    /// Mirrors the attached type's access level onto the generated members.
    ///
    /// A `public` type needs `public` witnesses to satisfy the conformance; anything else
    /// takes the default, since spelling `internal` out would be wrong for a `private` type.
    private static func accessLevelPrefix(of declaration: some DeclGroupSyntax) -> String {
        for modifier in declaration.modifiers where modifier.detail == nil {
            switch modifier.name.tokenKind {
            case .keyword(.public):
                return "public "
            case .keyword(.package):
                return "package "
            default:
                continue
            }
        }
        return ""
    }
}

public enum ObjectiveCBridgeableMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case notAValueType

    public var description: String {
        switch self {
        case .notAValueType:
            // Not a stylistic restriction: `_ObjectiveCBridgeable` is only consulted for
            // value types, so every generated witness would sit there unused on a class.
            return """
                @ObjectiveCBridgeable can only be applied to a struct or an enum. \
                `_ObjectiveCBridgeable` is only consulted for value types — a class is always \
                bridged verbatim, so the conformance would never be used.
                """
        }
    }

    public var message: String { description }

    public var diagnosticID: MessageID {
        MessageID(domain: "ObjectiveCBridgeableMacro", id: "notAValueType")
    }

    public var severity: DiagnosticSeverity { .error }
}
