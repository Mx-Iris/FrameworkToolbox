import MacroToolbox
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Makes a structure an `OptionSet` whose options are the cases of its nested
/// `Flag` enumeration, the raw value of each case being the position of its
/// bit.
public struct FlagSetMacro {}

// MARK: - The members

extension FlagSetMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let structure = declaration.as(StructDeclSyntax.self) else {
            context[.error, declaration] = "'@FlagSet' must be applied to a struct"
            return []
        }

        let flagSet: Reading
        switch read(structure) {
        case .success(let reading):
            flagSet = reading
        case .failure(let failure):
            context.diagnose(failure.diagnostic)
            return []
        }

        for misplacedBit in flagSet.bitsOutOfRange {
            context[.error, misplacedBit.node] = misplacedBit.message
        }

        return flagSet.members
    }
}

// MARK: - The conformance

extension FlagSetMacro: ExtensionMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) -> [ExtensionDeclSyntax] {
        // The member role reports every mistake. Adding the conformance on top
        // of one would bury it under errors about members that were never
        // generated.
        guard !protocols.isEmpty,
              let structure = declaration.as(StructDeclSyntax.self),
              case .success = read(structure)
        else {
            return []
        }

        // `nonisolated`: in a module whose default isolation is `MainActor`,
        // the conformance would otherwise be main-actor isolated, and the set
        // unusable as an `OptionSet` anywhere else.
        let conformance: DeclSyntax = """
        nonisolated extension \(type.trimmed): Swift.OptionSet {}
        """
        return [conformance.cast(ExtensionDeclSyntax.self)]
    }
}

// MARK: - Reading the structure

extension FlagSetMacro {
    /// What the macro reads off the structure it is attached to.
    struct Reading {
        let structure: StructDeclSyntax
        let flag: EnumDeclSyntax
        let rawValueType: TypeSyntax
        /// How many bits `rawValueType` holds, when it is spelled as one of the
        /// standard library's integer types, and `nil` for any other spelling,
        /// such as a typealias, which is then not checked.
        let bitWidth: Int?
    }

    struct ReadingFailure: Error {
        let diagnostic: Diagnostic
    }

    static func read(_ structure: StructDeclSyntax) -> Result<Reading, ReadingFailure> {
        let flag = structure.memberBlock.members.lazy
            .compactMap { member in member.decl.as(EnumDeclSyntax.self) }
            .first { enumeration in enumeration.name.unescaped == "Flag" }

        guard let flag else {
            return .failure(ReadingFailure(diagnostic: Diagnostic(
                node: structure.name,
                message: MacroExpansionErrorMessage(
                    "'@FlagSet' needs an 'enum Flag' declared in the body of "
                        + "'\(structure.name.text)', whose cases are the flags of the set"
                )
            )))
        }

        guard let inheritanceClause = flag.inheritanceClause,
              let firstInheritedType = inheritanceClause.inheritedTypes.first
        else {
            let fixedFlag = flag
                .with(\.name, flag.name.with(\.trailingTrivia, []))
                .with(
                    \.inheritanceClause,
                    InheritanceClauseSyntax(
                        colon: .colonToken(trailingTrivia: .space),
                        inheritedTypes: InheritedTypeListSyntax([InheritedTypeSyntax(type: integerType)])
                    )
                    .with(\.trailingTrivia, flag.name.trailingTrivia)
                )
            return .failure(missingRawType(on: flag, fixedFlag: fixedFlag))
        }

        let spelling = firstInheritedType.type.standardLibrarySpelling

        // A raw type has to be written first, so a protocol there means the
        // enumeration has none.
        if protocolsThatAreNotRawTypes.contains(spelling) {
            let rawType = InheritedTypeSyntax(
                type: integerType,
                trailingComma: .commaToken(trailingTrivia: .space)
            )
            let fixedFlag = flag.with(
                \.inheritanceClause,
                inheritanceClause.with(
                    \.inheritedTypes,
                    InheritedTypeListSyntax([rawType] + Array(inheritanceClause.inheritedTypes))
                )
            )
            return .failure(missingRawType(on: flag, fixedFlag: fixedFlag))
        }

        if rawTypesThatAreNotIntegers.contains(spelling) {
            return .failure(ReadingFailure(diagnostic: Diagnostic(
                node: firstInheritedType.type,
                message: MacroExpansionErrorMessage(
                    "'Flag' needs an integer raw type, not '\(firstInheritedType.type.trimmedDescription)': "
                        + "the raw value of each case is the position of its bit"
                )
            )))
        }

        return .success(Reading(
            structure: structure,
            flag: flag,
            rawValueType: firstInheritedType.type.trimmed,
            bitWidth: integerBitWidths[spelling]
        ))
    }

    private static var integerType: TypeSyntax {
        TypeSyntax(IdentifierTypeSyntax(name: .identifier("Int")))
    }

    private static func missingRawType(on flag: EnumDeclSyntax, fixedFlag: EnumDeclSyntax) -> ReadingFailure {
        ReadingFailure(diagnostic: Diagnostic(
            node: flag.name,
            message: MacroExpansionErrorMessage(
                "'Flag' needs an integer raw type: the raw value of each case is the position of its bit"
            ),
            fixIt: .replace(
                message: MacroExpansionFixItMessage("add 'Int' as the raw type"),
                oldNode: flag,
                newNode: fixedFlag
            )
        ))
    }

    /// The width of each standard library integer type. `Int` and `UInt` are
    /// 64 bits everywhere but arm64_32 watchOS, where they are 32; a macro
    /// cannot know which platform the caller builds for, so the wider width is
    /// checked and the narrower one is left to the documentation.
    private static let integerBitWidths: [String: Int] = [
        "Int": 64, "UInt": 64,
        "Int8": 8, "UInt8": 8,
        "Int16": 16, "UInt16": 16,
        "Int32": 32, "UInt32": 32,
        "Int64": 64, "UInt64": 64,
        "Int128": 128, "UInt128": 128,
    ]

    private static let rawTypesThatAreNotIntegers: Set<String> = [
        "String", "Character", "Unicode.Scalar",
        "Double", "Float", "Float16", "Float80", "CGFloat",
    ]

    private static let protocolsThatAreNotRawTypes: Set<String> = [
        "CaseIterable", "Sendable", "BitwiseCopyable",
        "Equatable", "Hashable", "Comparable", "Identifiable",
        "Codable", "Encodable", "Decodable",
        "CustomStringConvertible", "CustomDebugStringConvertible",
    ]
}

// MARK: - Generating the members

extension FlagSetMacro.Reading {
    var members: [DeclSyntax] {
        let memberAccess = self.memberAccess
        let initializerAccess = min(memberAccess, FlagSetMacro.AccessLevel(flag.modifiers) ?? .internal)

        var declarations: [DeclSyntax] = [
            "nonisolated \(raw: memberAccess.modifier)let rawValue: \(rawValueType)",
            """
            \(raw: memberAccess.inlinableAttribute)nonisolated \(raw: memberAccess.modifier)init(rawValue: \(rawValueType)) {
                self.rawValue = rawValue
            }
            """,
            """
            \(raw: flagAvailability)\(raw: initializerAccess.inlinableAttribute)nonisolated \(raw: initializerAccess.modifier)\
            init(_ flag: \(raw: flag.name.text)) {
                self.init(rawValue: 1 << flag.rawValue)
            }
            """,
        ]

        declarations += staticFlags(in: flag.memberBlock.members).map { declaration in
            DeclSyntax(stringLiteral: declaration)
        }

        return declarations
    }

    /// The access level of the members that are part of the set's interface.
    ///
    /// A member of a type is never visible beyond the type itself, so the
    /// structure's level is only written out when it is above `internal`; below
    /// it, the unwritten default already means "as visible as the structure".
    private var memberAccess: FlagSetMacro.AccessLevel {
        let structureAccess = FlagSetMacro.AccessLevel(structure.modifiers) ?? .internal
        return max(.internal, min(structureAccess, .public))
    }

    /// `@available` attributes of `Flag`, one per line, for every member that
    /// names it.
    private var flagAvailability: String {
        Self.availability(flag.attributes)
    }

    private static func availability(_ attributes: AttributeListSyntax) -> String {
        attributes.mirroredAsTypeForMember.map { attribute in "\(attribute.trimmedDescription)\n" }.joined()
    }

    /// One static per case, in the order the cases are declared, with any `#if`
    /// around a case reproduced around its static.
    private func staticFlags(in members: MemberBlockItemListSyntax) -> [String] {
        var declarations: [String] = []

        for member in members {
            if let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) {
                // One documentation comment and one set of attributes cover
                // every element of `case a, b`, as they do in the enumeration.
                let preamble = caseDeclaration.documentation
                    + flagAvailability
                    + Self.availability(caseDeclaration.attributes)

                for element in caseDeclaration.elements {
                    declarations.append(
                        "\(preamble)nonisolated \(memberAccess.modifier)static let \(element.name.text) = "
                            + "Self(.\(element.name.text))"
                    )
                }
            } else if let conditional = member.decl.as(IfConfigDeclSyntax.self) {
                var containsFlags = false
                var text = ""

                for clause in conditional.clauses {
                    text += clause.poundKeyword.text
                    if let condition = clause.condition {
                        text += " \(condition.trimmedDescription)"
                    }
                    text += "\n"

                    if case .decls(let nestedMembers)? = clause.elements {
                        let nestedDeclarations = staticFlags(in: nestedMembers)
                        containsFlags = containsFlags || !nestedDeclarations.isEmpty
                        text += nestedDeclarations.map { declaration in "\(declaration)\n" }.joined()
                    }
                }

                if containsFlags {
                    declarations.append(text + "#endif")
                }
            }
        }

        return declarations
    }
}

// MARK: - Checking the bit positions

extension FlagSetMacro.Reading {
    /// A case whose bit cannot be set: `1 << position` is `0` for a negative
    /// position and for one at or beyond the width of the raw type, so the
    /// flag would be an empty set and `contains` would hold for every set.
    struct BitOutOfRange {
        let node: Syntax
        let message: String
    }

    /// Every case whose position is known from the source and lies outside
    /// the raw type. A position that depends on which `#if` branch is active,
    /// or that follows a raw value which is not an integer literal, is not
    /// known and not checked.
    var bitsOutOfRange: [BitOutOfRange] {
        var findings: [BitOutOfRange] = []
        var nextImplicitPosition: Int? = 0
        collectBitsOutOfRange(in: flag.memberBlock.members, nextImplicitPosition: &nextImplicitPosition, into: &findings)
        return findings
    }

    private func collectBitsOutOfRange(
        in members: MemberBlockItemListSyntax,
        nextImplicitPosition: inout Int?,
        into findings: inout [BitOutOfRange]
    ) {
        for member in members {
            if let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) {
                for element in caseDeclaration.elements {
                    let position: Int?
                    let node: Syntax
                    if let rawValue = element.rawValue {
                        position = Self.integerValue(of: rawValue.value)
                        node = Syntax(rawValue.value)
                    } else {
                        position = nextImplicitPosition
                        node = Syntax(element.name)
                    }

                    guard let position else {
                        nextImplicitPosition = nil
                        continue
                    }

                    if let finding = check(position, of: element, at: node) {
                        findings.append(finding)
                    }
                    nextImplicitPosition = position == .max ? nil : position + 1
                }
            } else if let conditional = member.decl.as(IfConfigDeclSyntax.self) {
                // Each branch continues from the case before the `#if`. What
                // follows the `#if` is known only when every way through it,
                // including taking no branch, ends at the same position.
                var endings: [Int?] = []
                var hasElse = false

                for clause in conditional.clauses {
                    if clause.poundKeyword.tokenKind == .poundElse {
                        hasElse = true
                    }
                    var branchPosition = nextImplicitPosition
                    if case .decls(let nestedMembers)? = clause.elements {
                        collectBitsOutOfRange(in: nestedMembers, nextImplicitPosition: &branchPosition, into: &findings)
                    }
                    endings.append(branchPosition)
                }
                if !hasElse {
                    endings.append(nextImplicitPosition)
                }

                if let firstEnding = endings.first, endings.allSatisfy({ ending in ending == firstEnding }) {
                    nextImplicitPosition = firstEnding
                } else {
                    nextImplicitPosition = nil
                }
            }
        }
    }

    private func check(_ position: Int, of element: EnumCaseElementSyntax, at node: Syntax) -> BitOutOfRange? {
        let name = element.name.text

        if position < 0 {
            return BitOutOfRange(
                node: node,
                message: "bit position \(position) is negative; '1 << \(position)' is 0, "
                    + "so '\(name)' would be an empty set"
            )
        }

        if let bitWidth, position >= bitWidth {
            return BitOutOfRange(
                node: node,
                message: "bit position \(position) does not fit in '\(rawValueType.trimmedDescription)', "
                    + "which has \(bitWidth) bits; '1 << \(position)' is 0, so '\(name)' would be an empty set"
            )
        }

        return nil
    }

    /// The value of an integer literal raw value, written with or without a
    /// minus sign — the only forms Swift accepts for an integer raw value.
    private static func integerValue(of expression: ExprSyntax) -> Int? {
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            return literal.representedLiteralValue
        }
        if let negation = expression.as(PrefixOperatorExprSyntax.self),
           negation.operator.text == "-",
           let literal = negation.expression.as(IntegerLiteralExprSyntax.self),
           let magnitude = literal.representedLiteralValue {
            return -magnitude
        }
        return nil
    }
}

// MARK: - Access levels

extension FlagSetMacro {
    enum AccessLevel: Int, Comparable {
        case `private`
        case `fileprivate`
        case `internal`
        case `package`
        case `public`

        /// The access level a declaration spells out, ignoring setter-only
        /// modifiers such as `private(set)`; `open` counts as `public`, which is
        /// all a member of a structure can be.
        init?(_ modifiers: DeclModifierListSyntax) {
            for modifier in modifiers where modifier.detail == nil {
                switch modifier.name.tokenKind {
                case .keyword(.private): self = .private
                case .keyword(.fileprivate): self = .fileprivate
                case .keyword(.internal): self = .internal
                case .keyword(.package): self = .package
                case .keyword(.public), .keyword(.open): self = .public
                default: continue
                }
                return
            }
            return nil
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// The modifier to write, followed by a space, or nothing for
        /// `internal`, which is the default.
        var modifier: String {
            switch self {
            case .private: "private "
            case .fileprivate: "fileprivate "
            case .internal: ""
            case .package: "package "
            case .public: "public "
            }
        }

        /// `@inlinable` is only accepted on a declaration visible outside its
        /// module.
        var inlinableAttribute: String {
            self >= .package ? "@inlinable " : ""
        }
    }
}

// MARK: - Syntax helpers

extension TypeSyntax {
    /// The type as written, without a leading `Swift.` — so that `Swift.Int`
    /// is recognized as `Int`.
    fileprivate var standardLibrarySpelling: String {
        let spelling = trimmedDescription
        let qualifier = "Swift."
        return spelling.hasPrefix(qualifier) ? String(spelling.dropFirst(qualifier.count)) : spelling
    }
}

extension EnumCaseDeclSyntax {
    /// The case's documentation comment, one comment per line, ready to put in
    /// front of a declaration generated from it.
    fileprivate var documentation: String {
        leadingTrivia.compactMap { piece -> String? in
            switch piece {
            case .docLineComment(let text), .docBlockComment(let text): "\(text)\n"
            default: nil
            }
        }.joined()
    }
}
