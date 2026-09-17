import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates the `_ObjectiveCBridgeable` witnesses for a struct that wraps an Objective-C
/// object in a `rawValue` property.
///
/// ## Why this is a macro rather than a protocol extension
///
/// The four methods are identical across every handle, so a default implementation in a
/// protocol extension is the obvious way to write them once — and it costs the entire
/// optimization. Measured by reading optimized SIL of a bridge-to-Swift-and-straight-back
/// round trip, three configurations behave as follows:
///
/// | Witness lives in | `@_semantics` | Round trip |
/// |---|---|---|
/// | protocol extension | present | **not** eliminated |
/// | concrete type | absent | **not** eliminated |
/// | concrete type | present | eliminated, down to `return %0` |
///
/// Both conditions are load-bearing. `objc-bridging-optimization` requires
/// `arguments.count == 2` with a `.directGuaranteed` first argument, and a default
/// implementation has an opaque `Self` that must travel indirectly (`@out` one way,
/// `@in_guaranteed` the other) — so the pass never matches it. Emitting the witnesses onto
/// the concrete type fixes the calling convention; the `@_semantics` pair is what makes the
/// pass recognise them as bridging functions at all.
///
/// Which leaves one method per type per direction to keep correct by hand, across six types,
/// where dropping a single underscored attribute silently returns the optimization to zero
/// with no diagnostic anywhere. That is the job this macro exists to do.
///
/// ## What the attached type must provide
///
/// - `var rawValue: <an Objective-C class>` — a stored property with an explicit type
///   annotation. Its type becomes `_ObjectiveCType`.
/// - `init(rawValue:)` and `init()`.
/// - `static func containsOnlyExpectedElementTypes(in:) -> Bool`, which backs `as?`.
///
/// Conforming to ``ObjectiveCCollectionHandle`` is the way to get all four checked by the
/// compiler rather than discovered in a macro expansion.
public struct ObjectiveCBridgeableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: ObjectiveCBridgeableMacroError.notAStruct))
            return []
        }

        guard let objectiveCType = objectiveCTypeOfRawValue(in: structDeclaration) else {
            context.diagnose(Diagnostic(node: node, message: ObjectiveCBridgeableMacroError.missingRawValue))
            return []
        }

        let accessLevel = accessLevelPrefix(of: structDeclaration)

        let extensionDeclaration = try ExtensionDeclSyntax(
            """
            extension \(type.trimmed): _ObjectiveCBridgeable {
                \(raw: accessLevel)typealias _ObjectiveCType = \(objectiveCType)

                // Paired with `bridgeFromObjectiveC` below; the optimizer's round-trip
                // elimination only fires when it recognises both halves.
                @_semantics("convertToObjectiveC")
                \(raw: accessLevel)func _bridgeToObjectiveC() -> \(objectiveCType) {
                    rawValue
                }

                // This direction is allowed to defer element checking — it is what lets
                // `as!` skip the walk — so it does not validate.
                \(raw: accessLevel)static func _forceBridgeFromObjectiveC(
                    _ source: \(objectiveCType),
                    result: inout Self?
                ) {
                    result = Self(rawValue: source)
                }

                @discardableResult
                \(raw: accessLevel)static func _conditionallyBridgeFromObjectiveC(
                    _ source: \(objectiveCType),
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
                \(raw: accessLevel)static func _unconditionallyBridgeFromObjectiveC(
                    _ source: \(objectiveCType)?
                ) -> Self {
                    guard let source else { return Self() }
                    return Self(rawValue: source)
                }
            }
            """
        )

        return [extensionDeclaration]
    }

    /// The declared type of the stored `rawValue` property, which becomes `_ObjectiveCType`.
    ///
    /// Read syntactically, so the annotation has to be written out — there is no type
    /// checker at expansion time to infer it from an initializer.
    private static func objectiveCTypeOfRawValue(in declaration: StructDeclSyntax) -> TypeSyntax? {
        for member in declaration.memberBlock.members {
            guard let variableDeclaration = member.decl.as(VariableDeclSyntax.self),
                  !variableDeclaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }),
                  let binding = variableDeclaration.bindings.first,
                  binding.accessorBlock == nil,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  identifier.identifier.text == "rawValue",
                  let typeAnnotation = binding.typeAnnotation
            else { continue }
            return typeAnnotation.type.trimmed
        }
        return nil
    }

    /// Mirrors the attached type's access level onto the generated members.
    ///
    /// A `public` type needs `public` witnesses to satisfy the conformance; anything else
    /// takes the default, since spelling `internal` out would also be wrong for `private`.
    private static func accessLevelPrefix(of declaration: StructDeclSyntax) -> String {
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
    case notAStruct
    case missingRawValue

    public var description: String {
        switch self {
        case .notAStruct:
            // Not a stylistic restriction: `_ObjectiveCBridgeable` is only consulted for
            // value types, so the protocol would be skipped entirely on a class.
            return """
                @ObjectiveCBridgeable can only be applied to a struct. `_ObjectiveCBridgeable` \
                is only consulted for value types — a class is always bridged verbatim, so the \
                conformance would never be used.
                """
        case .missingRawValue:
            return """
                @ObjectiveCBridgeable requires a stored `rawValue` property with an explicit \
                type annotation naming the Objective-C class to bridge to, for example \
                `let rawValue: NSArray`.
                """
        }
    }

    public var message: String { description }

    public var diagnosticID: MessageID {
        switch self {
        case .notAStruct:
            MessageID(domain: "ObjectiveCBridgeableMacro", id: "notAStruct")
        case .missingRawValue:
            MessageID(domain: "ObjectiveCBridgeableMacro", id: "missingRawValue")
        }
    }

    public var severity: DiagnosticSeverity { .error }
}
