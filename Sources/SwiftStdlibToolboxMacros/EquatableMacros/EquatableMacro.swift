import Foundation
import MacroToolbox
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Source: https://github.com/ordo-one/equatable

/// A macro that automatically generates an `Equatable` conformance for structs.
///
/// This macro creates a standard equality implementation by comparing all stored properties
/// that aren't explicitly marked to be skipped with `@EquatableIgnored`.
/// Properties with SwiftUI property wrappers (like `@State`, `@ObservedObject`, etc.)
///
/// Structs with arbitary closures are not supported unless they are marked explicitly with `@EquatableIgnoredUnsafeClosure` -
/// meaning that they are safe because they don't  influence rendering of the view's body.
///
/// Usage:
/// ```swift
/// import Equatable
/// import SwiftUI
///
/// @Equatable
/// struct ProfileView: View {
///     var username: String   // Will be compared
///     @State private var isLoading = false           // Automatically skipped
///     @ObservedObject var viewModel: ProfileViewModel // Automatically skipped
///     @EquatableIgnored var cachedValue: String? // This property will be excluded
///     @EquatableIgnoredUnsafeClosure var onTap: () -> Void // This closure is safe and will be ignored in comparison
///     let id: UUID // will be compared first for shortcircuiting equality checks
///
///     var body: some View {
///         VStack {
///             Text(username)
///             if isLoading {
///                 ProgressView()
///             }
///         }
///     }
/// }
/// ```
///
/// The generated extension will implement the `==` operator with property comparisons
/// ordered for optimal performance (e.g., IDs and simple types first):
/// ```swift
/// extension ProfileView: Equatable {
///     nonisolated public static func == (lhs: ProfileView, rhs: ProfileView) -> Bool {
///         lhs.id == rhs.id && lhs.username == rhs.username
///     }
/// }
/// ```
///
/// If the type is marked as conforming to `Hashable` the compiler synthesized `Hashable` implementation will not be correct.
/// That's why the `@Equatable` macro will also generate a `Hashable` implementation for the type that is aligned with the `Equatable` implementation.
///
/// ```swift
/// import Equatable
/// @Equatable
/// struct User: Hashable {
///     let id: Int
///     @EquatableIgnored var name = ""
/// }
/// ```
///
/// Expanded:
/// ```swift
/// extension User: Equatable {
///     nonisolated public static func == (lhs: User, rhs: User) -> Bool {
///         lhs.id == rhs.id
///     }
/// }
/// extension User {
///     nonisolated public func hash(into hasher: inout Hasher) {
///         hasher.combine(id)
///     }
/// }
/// ```
///

protocol TypeDeclSyntax: DeclSyntaxProtocol {
    var memberBlock: MemberBlockSyntax { get }
    var inheritanceClause: InheritanceClauseSyntax? { get }
}

extension StructDeclSyntax: TypeDeclSyntax {}
extension ClassDeclSyntax: TypeDeclSyntax {}

public struct EquatableMacro: ExtensionMacro {
    private static let skippablePropertyWrappers: Set = [
        "AccessibilityFocusState",
        "AppStorage",
        "Bindable",
        "Environment",
        "EnvironmentObject",
        "FetchRequest",
        "FocusState",
        "FocusedObject",
        "FocusedValue",
        "GestureState",
        "NSApplicationDelegateAdaptor",
        "Namespace",
        "ObservedObject",
        "PhysicalMetric",
        "ScaledMetric",
        "SceneStorage",
        "SectionedFetchRequest",
        "State",
        "StateObject",
        "UIApplicationDelegateAdaptor",
        "WKApplicationDelegateAdaptor",
        "WKExtensionDelegateAdaptor",
    ]

    // swiftlint:disable:next function_body_length
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Ensure we're attached to a struct

        let typeDecl: TypeDeclSyntax

        if let structDecl = declaration.as(StructDeclSyntax.self) {
            typeDecl = structDecl
        } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
            typeDecl = classDecl
        } else {
            let diagnostic = Diagnostic(
                node: node,
                message: MacroExpansionErrorMessage("@Equatable can only be applied to structs or classes")
            )
            context.diagnose(diagnostic)
            return []
        }

        // Extract stored properties
        var storedProperties: [(name: String, type: TypeSyntax?)] = []
        for member in typeDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  binding.accessorBlock == nil,
                  !varDecl.isStatic else {
                continue
            }

            if Self.shouldSkip(varDecl) {
                continue
            }

            if isMarkedWithEquatableIgnoredUnsafeClosure(varDecl) {
                continue
            }

            // Check if it's a closure that should trigger diagnostic
            let isClosureProperty = (binding.typeAnnotation?.type).map(isClosure) == true ||
                (binding.initializer?.value.is(ClosureExprSyntax.self) ?? false)

            if isClosureProperty {
                let diagnostic = Self.makeClosureDiagnostic(for: varDecl)
                context.diagnose(diagnostic)
                continue
            }

            storedProperties.append((name: identifier, type: binding.typeAnnotation?.type))
        }

        // Sort properties: "id" first, then by type complexity
        let sortedProperties = storedProperties.sorted { lhs, rhs in
            return Self.compare(lhs: lhs, rhs: rhs)
        }

        guard let extensionSyntax = Self.generateEquatableExtensionSyntax(
            sortedProperties: sortedProperties,
            type: type
        ) else {
            return []
        }

        // If the type conforms to `Hashable`, always generate a corresponding hash function aligned with the `Equatable` implementation
        if typeDecl.declaresHashable || Self.compilerReportsHashableConformance(in: protocols) {
            guard let hashableExtensionSyntax = Self.generateHashableExtensionSyntax(
                sortedProperties: sortedProperties,
                type: type
            ) else {
                return [extensionSyntax]
            }
            return [extensionSyntax, hashableExtensionSyntax]
        } else {
            return [extensionSyntax]
        }
    }
}

extension EquatableMacro {
    /// Whether the compiler says the type already conforms to `Hashable`,
    /// wherever that conformance is declared.
    ///
    /// The compiler passes an extension macro the protocols from its
    /// `conformances:` list that the type does *not* conform to yet, so a
    /// `Hashable` missing from the list means the type has it. That reading
    /// needs the list to come from the compiler at all: swift-macro-testing
    /// passes an empty one for every type, which would make everything
    /// Hashable. `_EquatableConformanceSentinel` is listed in the macro's
    /// declaration and never conformed to, so it is present exactly when the
    /// compiler filled the list in; without it the macro falls back to reading
    /// the inheritance clause.
    ///
    /// The compiler's answer covers conformances declared directly, in the type
    /// or in any extension, but not one implied by a refined protocol
    /// (`protocol Record: Hashable`): that one is reported missing — measured on
    /// `ObjectiveCCollectionHandle`, which refines `ObjectiveCRepresentable`.
    /// Such a type falls back to the inheritance clause like before.
    private static func compilerReportsHashableConformance(in protocols: [TypeSyntax]) -> Bool {
        let compilerFilledTheList = protocols.contains { protocolType in
            protocolType.trimmedDescription.split(separator: ".").last == "_EquatableConformanceSentinel"
        }
        return compilerFilledTheList && !protocols.contains { $0.namesHashable }
    }

    // Skip properties with SwiftUI attributes (like @State, @Binding, etc.) or if they are marked with @EqutableIgnored
    private static func shouldSkip(_ varDecl: VariableDeclSyntax) -> Bool {
        varDecl.attributes.contains { attribute in
            if let atribute = attribute.as(AttributeSyntax.self),
               shouldSkip(atribute: atribute) {
                return true
            }
            return false
        }
    }

    private static func shouldSkip(atribute node: AttributeSyntax) -> Bool {
        if let identifierType = node.attributeName.as(IdentifierTypeSyntax.self),
           shouldSkip(identifierType: identifierType) {
            return true
        }
        if let memberType = node.attributeName.as(MemberTypeSyntax.self),
           Self.shouldSkip(memberType: memberType) {
            return true
        }
        return false
    }

    private static func shouldSkip(identifierType node: IdentifierTypeSyntax) -> Bool {
        if node.name.text == "EquatableIgnored" {
            return true
        }
        if skippablePropertyWrappers.contains(node.name.text) {
            return true
        }
        return false
    }

    private static func shouldSkip(memberType node: MemberTypeSyntax) -> Bool {
        // The marker may be reached through any module that re-exports it.
        if node.name.text == "EquatableIgnored" {
            return true
        }
        if node.baseType.as(IdentifierTypeSyntax.self)?.name.text == "SwiftUI",
           skippablePropertyWrappers.contains(node.name.text) {
            return true
        }
        return false
    }

    private static func isMarkedWithEquatableIgnoredUnsafeClosure(_ varDecl: VariableDeclSyntax) -> Bool {
        varDecl.attributes.contains(where: { attribute in
            attribute.as(AttributeSyntax.self)?.unqualifiedName == "EquatableIgnoredUnsafeClosure"
        })
    }

    private static func compare(lhs: (name: String, type: TypeSyntax?), rhs: (name: String, type: TypeSyntax?)) -> Bool {
        // "id" always comes first
        if lhs.name == "id" { return true }
        if rhs.name == "id" { return false }

        let lhsComplexity = typeComplexity(lhs.type)
        let rhsComplexity = typeComplexity(rhs.type)

        if lhsComplexity == rhsComplexity {
            return lhs.name < rhs.name
        }
        return lhsComplexity < rhsComplexity
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func typeComplexity(_ type: TypeSyntax?) -> Int {
        guard let type else { return 100 } // Unknown types go last

        let typeString = type.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        switch typeString {
        case "Bool": return 1
        case "Int",
             "Int8",
             "Int16",
             "Int32",
             "Int64": return 2
        case "UInt",
             "UInt8",
             "UInt16",
             "UInt32",
             "UInt64": return 3
        case "Float",
             "Double": return 4
        case "String": return 5
        case "Character": return 6
        case "Date": return 7
        case "Data": return 8
        case "URL": return 9
        case "UUID": return 10
        default:
            if type.is(OptionalTypeSyntax.self) {
                if let wrappedType = type.as(OptionalTypeSyntax.self)?.wrappedType {
                    return typeComplexity(wrappedType) + 20
                }
            }

            if type.isArray {
                return 30
            }

            if type.isDictionary {
                return 40
            }

            return 50
        }
    }

    private static func makeClosureDiagnostic(for varDecl: VariableDeclSyntax) -> Diagnostic {
        let attribute = AttributeSyntax(
            leadingTrivia: .space,
            atSign: .atSignToken(),
            attributeName: IdentifierTypeSyntax(name: .identifier("EquatableIgnoredUnsafeClosure")),
            trailingTrivia: .space
        )
        let existingAttributes = varDecl.attributes
        let newAttributes = existingAttributes + [.attribute(attribute.with(\.leadingTrivia, .space))]
        let fixedDecl = varDecl.with(\.attributes, newAttributes)
        let diagnostic = Diagnostic(
            node: varDecl,
            message: MacroExpansionErrorMessage("Arbitary closures are not supported in @Equatable"),
            fixIt: .replace(
                message: SimpleFixItMessage(
                    message: """
                    Consider marking the closure with\
                    @EquatableIgnoredUnsafeClosure if it doesn't effect the view's body output.
                    """,
                    fixItID: MessageID(
                        domain: "",
                        id: "test"
                    )
                ),
                oldNode: varDecl,
                newNode: fixedDecl
            )
        )

        return diagnostic
    }

    /// The extensions are `nonisolated` as well as their members. In a module
    /// whose default isolation is `MainActor` (SE-0466), an extension without
    /// it declares a main-actor-isolated conformance even though `==` itself is
    /// `nonisolated`, and every use of the type as `Equatable` — or as
    /// `Hashable`, which builds on it — from a background thread fails.
    private static func generateEquatableExtensionSyntax(
        sortedProperties: [(name: String, type: TypeSyntax?)],
        type: TypeSyntaxProtocol
    ) -> ExtensionDeclSyntax? {
        guard !sortedProperties.isEmpty else {
            let extensionDecl: DeclSyntax = """
            nonisolated extension \(type): Equatable {
                nonisolated public static func == (lhs: \(type), rhs: \(type)) -> Bool {
                    true
                }
            }
            """

            return extensionDecl.as(ExtensionDeclSyntax.self)
        }

        let comparisons = sortedProperties.map { property in
            "lhs.\(property.name) == rhs.\(property.name)"
        }.joined(separator: " && ")

        let equalityImplementation = comparisons.isEmpty ? "true" : comparisons

        let extensionDecl: DeclSyntax = """
        nonisolated extension \(type): Equatable {
            nonisolated public static func == (lhs: \(type), rhs: \(type)) -> Bool {
                \(raw: equalityImplementation)
            }
        }
        """

        return extensionDecl.as(ExtensionDeclSyntax.self)
    }

    private static func generateHashableExtensionSyntax(
        sortedProperties: [(name: String, type: TypeSyntax?)],
        type: TypeSyntaxProtocol
    ) -> ExtensionDeclSyntax? {
        guard !sortedProperties.isEmpty else {
            let hashableExtensionDecl: DeclSyntax = """
            nonisolated extension \(raw: type) {
                nonisolated public func hash(into hasher: inout Hasher) {}
            }
            """

            return hashableExtensionDecl.as(ExtensionDeclSyntax.self)
        }

        let hashableImplementation = sortedProperties.map { property in
            "hasher.combine(\(property.name))"
        }
        .joined(separator: "\n")

        let hashableExtensionDecl: DeclSyntax = """
        nonisolated extension \(raw: type) {
            nonisolated public func hash(into hasher: inout Hasher) {
                \(raw: hashableImplementation)
            }
        }
        """

        return hashableExtensionDecl.as(ExtensionDeclSyntax.self)
    }
}
