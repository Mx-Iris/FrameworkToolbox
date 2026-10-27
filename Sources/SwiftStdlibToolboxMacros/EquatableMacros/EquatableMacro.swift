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
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            switch Self.disposition(of: varDecl) {
            case .compared(let comparedMember):
                storedProperties.append((name: comparedMember.name, type: comparedMember.binding.typeAnnotation?.type))
            case .rejectedClosure:
                context.diagnose(Self.makeClosureDiagnostic(for: varDecl))
            case .notCompared:
                continue
            }
        }

        // Sort properties: "id" first, then by type complexity
        let sortedProperties = storedProperties.sorted { lhs, rhs in
            return Self.compare(lhs: lhs, rhs: rhs)
        }

        // A `Hashable` the inheritance clause names gets its `hash(into:)` here.
        // Any other type leaves the question to the compiler: `==` carries
        // `_EquatableHashing`, which writes the same `hash(into:)` only if the
        // type turns out to be `Hashable`. The compiler cannot be asked through
        // `conformances:` — see `_EquatableHashing`'s declaration for why.
        let hashingAttribute = typeDecl.declaresHashable
            ? nil
            : Self.hashingAttribute(for: type, sortedProperties: sortedProperties)

        guard let extensionSyntax = Self.generateEquatableExtensionSyntax(
            sortedProperties: sortedProperties,
            type: type,
            hashingAttribute: hashingAttribute
        ) else {
            return []
        }

        guard typeDecl.declaresHashable else {
            return [extensionSyntax]
        }
        guard let hashableExtensionSyntax = Self.generateHashableExtensionSyntax(
            sortedProperties: sortedProperties,
            type: type
        ) else {
            return [extensionSyntax]
        }
        return [extensionSyntax, hashableExtensionSyntax]
    }

    /// `@_EquatableHashing(<type>.self, members: [...])`, naming the compared
    /// members in the order `==` compares them.
    private static func hashingAttribute(
        for type: some TypeSyntaxProtocol,
        sortedProperties: [(name: String, type: TypeSyntax?)]
    ) -> String {
        let memberList = sortedProperties
            .map { "\"\($0.name)\"" }
            .joined(separator: ", ")
        return "@SwiftStdlibToolbox._EquatableHashing(\(type.trimmedDescription).self, members: [\(memberList)])"
    }

    /// The statements of the `hash(into:)` that agrees with `==`: one
    /// `combine` per compared member, in the order `==` compares them.
    static func hashCombinations(of memberNames: [String]) -> String {
        memberNames
            .map { "hasher.combine(\($0))" }
            .joined(separator: "\n")
    }
}

// MARK: - Which members are compared

extension EquatableMacro {
    /// A stored property `==` compares.
    struct ComparedMember {
        let name: String
        let binding: PatternBindingSyntax
    }

    enum MemberDisposition {
        case compared(ComparedMember)
        /// A closure the type has not marked as safe to ignore; diagnosed by
        /// the extension role, and only there.
        case rejectedClosure
        case notCompared
    }

    /// What `@Equatable` does with a member — the one decision both of its
    /// roles have to agree on.
    static func disposition(of varDecl: VariableDeclSyntax) -> MemberDisposition {
        guard let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              binding.accessorBlock == nil,
              !varDecl.isStatic else {
            return .notCompared
        }

        if Self.shouldSkip(varDecl) || isMarkedWithEquatableIgnoredUnsafeClosure(varDecl) {
            return .notCompared
        }

        let isClosureProperty = (binding.typeAnnotation?.type).map(isClosure) == true ||
            (binding.initializer?.value.is(ClosureExprSyntax.self) ?? false)
        if isClosureProperty {
            return .rejectedClosure
        }

        return .compared(ComparedMember(name: identifier, binding: binding))
    }
}

// MARK: - The member checks

extension EquatableMacro: MemberAttributeMacro {
    /// Attaches the check that has the compiler decide whether the member can be
    /// compared; see `_EquatableMemberCheck`. A member left unchecked behaves as
    /// before — a type that cannot be compared still fails, in the expansion of
    /// `==` — so each exclusion below only gives up the better diagnostic.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        let typeDecl: TypeDeclSyntax
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            typeDecl = structDecl
        } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
            typeDecl = classDecl
        } else {
            return []
        }

        guard let varDecl = member.as(VariableDeclSyntax.self),
              varDecl.bindings.count == 1,
              case .compared(let comparedMember) = disposition(of: varDecl),
              comparesDirectMember(named: comparedMember.name, of: typeDecl),
              let argument = checkArgument(for: comparedMember, in: varDecl)
        else {
            return []
        }

        // Only the inheritance clause is visible here, so a `Hashable` declared
        // in an extension elsewhere or implied by a refined protocol goes
        // unnoticed and the member is checked as `Equatable`; at worst the error
        // then lands in the expansion of `hash(into:)`, as it did before these
        // checks existed.
        let checkName = typeDecl.declaresHashable ? "_HashableMemberCheck" : "_EquatableMemberCheck"
        return ["@SwiftStdlibToolbox.\(raw: checkName)(\(raw: argument))"]
    }

    /// Whether `==` compares a member of this name. The compiler applies member
    /// attributes to the members of an active `#if` clause too, but the
    /// extension role only compares members declared directly in the type's
    /// body — checking the others would report members that are never compared.
    private static func comparesDirectMember(named name: String, of typeDecl: TypeDeclSyntax) -> Bool {
        typeDecl.memberBlock.members.contains { item in
            guard let varDecl = item.decl.as(VariableDeclSyntax.self),
                  case .compared(let comparedMember) = disposition(of: varDecl) else {
                return false
            }
            return comparedMember.name == name
        }
    }

    /// The argument that tells the check which type to test, or `nil` for the
    /// members `==` can compare without the type conforming.
    private static func checkArgument(
        for comparedMember: ComparedMember,
        in varDecl: VariableDeclSyntax
    ) -> String? {
        if let type = comparedMember.binding.typeAnnotation?.type.trimmed {
            // A tuple of Equatable values and a metatype both compare with `==`
            // through standard library overloads, yet neither conforms.
            if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count != 1 {
                return nil
            }
            if type.is(MetatypeTypeSyntax.self) {
                return nil
            }
            return "type: \(metatypeExpression(for: type))"
        }

        guard let initialValue = comparedMember.binding.initializer?.value.trimmed else {
            return nil
        }
        // A lazy initial value may refer to `self`, which an attribute argument
        // cannot; tuples and metatypes compare without conforming, as above.
        if varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.lazy) }) {
            return nil
        }
        if let tuple = initialValue.as(TupleExprSyntax.self), tuple.elements.count != 1 {
            return nil
        }
        if let memberAccess = initialValue.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.tokenKind == .keyword(.self) {
            return nil
        }
        return "initialValue: \(initialValue)"
    }

    /// `T.self`, spelled so that `.self` applies to all of `T`. An implicitly
    /// unwrapped optional is not a type of its own outside a declaration, so it
    /// is checked as the optional it stands for.
    private static func metatypeExpression(for type: TypeSyntax) -> String {
        if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return "\(implicitlyUnwrapped.wrappedType.wrappedInOptional).self"
        }
        let needsParentheses = type.is(FunctionTypeSyntax.self)
            || type.is(SomeOrAnyTypeSyntax.self)
            || type.is(CompositionTypeSyntax.self)
            || type.is(AttributedTypeSyntax.self)
        return needsParentheses ? "(\(type)).self" : "\(type).self"
    }
}

extension EquatableMacro {
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
    ///
    /// `hashingAttribute` goes on `==` itself: a peer macro attached there puts
    /// the `hash(into:)` it writes into this same extension.
    private static func generateEquatableExtensionSyntax(
        sortedProperties: [(name: String, type: TypeSyntax?)],
        type: TypeSyntaxProtocol,
        hashingAttribute: String?
    ) -> ExtensionDeclSyntax? {
        let comparisons = sortedProperties.map { property in
            "lhs.\(property.name) == rhs.\(property.name)"
        }.joined(separator: " && ")

        let equalityImplementation = comparisons.isEmpty ? "true" : comparisons
        let attributeLine = hashingAttribute.map { "\($0)\n" } ?? ""

        let extensionDecl: DeclSyntax = """
        nonisolated extension \(type): Equatable {
            \(raw: attributeLine)nonisolated public static func == (lhs: \(type), rhs: \(type)) -> Bool {
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

        let hashableImplementation = Self.hashCombinations(of: sortedProperties.map { property in property.name })

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
