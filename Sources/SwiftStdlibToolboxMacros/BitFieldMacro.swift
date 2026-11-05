import MacroToolbox
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Makes a property read its value out of some bits of the enclosing type's
/// `rawValue`.
///
/// The getter it generates does not decide how to convert the bits: it hands
/// the property's type to `SwiftStdlibToolbox._BitFieldAccess`, whose
/// overloads the compiler chooses between. The macro sees spelling only, and
/// would take `typealias RawValue = UInt32` for an enumeration.
public struct BitFieldMacro {}

extension BitFieldMacro: AccessorMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) -> [AccessorDeclSyntax] {
        guard let property = declaration.as(VariableDeclSyntax.self) else {
            context[.error, attribute] = "'@BitField' must be applied to a property"
            return []
        }

        guard let field = Field(reading: property, in: context),
              let configuration = Configuration(decoding: attribute, in: context)
        else {
            return []
        }

        if let mismatch = field.mismatch(with: configuration.bits) {
            context[.error, configuration.bits.node] = mismatch
            return []
        }

        return [field.getter(reading: configuration, in: context)]
    }
}

// MARK: - The arguments

extension BitFieldMacro {
    struct Configuration {
        let bits: BitRange
        /// The `default:` argument as written, for bits the property's type
        /// does not know. Copied into the getter unchanged.
        let defaultValue: ExprSyntax?
    }
}

extension BitFieldMacro.Configuration: ExpressionListDecodable {
    enum ArgumentKey: String, Sendable {
        case bits
        case `default`
    }

    init(from arguments: inout ExpressionListDecoder<ArgumentKey>) throws {
        let bits: BitFieldMacro.BitRange = try arguments[.bits].decode()
        self.init(bits: bits, defaultValue: arguments[.default]?.value)
    }
}

extension BitFieldMacro {
    /// The bits a property occupies, as a half-open range of positions.
    struct BitRange: CustomStringConvertible {
        let lowerBound: Int
        let upperBound: Int
        /// The argument the range was read from, for diagnostics about it.
        let node: ExprSyntax

        var width: Int {
            upperBound - lowerBound
        }

        var description: String {
            "\(lowerBound)..<\(upperBound)"
        }
    }
}

extension BitFieldMacro.BitRange: ExpressionDecodable {
    /// Reads a single position, `5`, or a half-open range of them, `2..<8`,
    /// all written as integer literals: the macro needs the numbers while it
    /// expands, before anything is evaluated.
    init(from node: borrowing ExprSyntax) throws(ExpressionDecodingError) {
        let expression = copy node

        if let position = try Self.position(expression) {
            self.init(lowerBound: position, upperBound: position + 1, node: expression)
            return
        }

        guard let bounds = Self.halfOpenBounds(of: expression),
              let lowerBound = try Self.position(bounds.lower),
              let upperBound = try Self.position(bounds.upper)
        else {
            throw ExpressionDecodingError(
                text: "expected a bit position or a half-open range of them written as integer literals, "
                    + "such as '5' or '2..<8'",
                node: expression
            )
        }

        guard lowerBound < upperBound else {
            throw ExpressionDecodingError(
                text: "\(lowerBound)..<\(upperBound) holds no bits",
                node: expression
            )
        }

        self.init(lowerBound: lowerBound, upperBound: upperBound, node: expression)
    }

    /// The value of an integer literal, or `nil` for any other expression.
    /// A negative literal is an error rather than `nil`: it is a position,
    /// just not one that exists.
    private static func position(_ expression: ExprSyntax) throws(ExpressionDecodingError) -> Int? {
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            guard let value = literal.representedLiteralValue else {
                throw ExpressionDecodingError(
                    text: "bit position \(literal.literal.text) does not fit in 'Int'",
                    node: literal
                )
            }
            return value
        }

        if let negation = expression.as(PrefixOperatorExprSyntax.self),
           negation.operator.text == "-",
           negation.expression.is(IntegerLiteralExprSyntax.self) {
            throw ExpressionDecodingError(
                text: "bit position \(negation.trimmedDescription) is negative; bit 0 is the least significant",
                node: negation
            )
        }

        return nil
    }

    /// The operands of `lower..<upper`. The parser hands a macro its
    /// arguments with operators not yet folded, so the range normally arrives
    /// as a three-element sequence; a folded one is accepted too.
    private static func halfOpenBounds(of expression: ExprSyntax) -> (lower: ExprSyntax, upper: ExprSyntax)? {
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let rangeOperator = elements[1].as(BinaryOperatorExprSyntax.self),
                  rangeOperator.operator.text == "..<"
            else {
                return nil
            }
            return (elements[0], elements[2])
        }

        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let rangeOperator = infix.operator.as(BinaryOperatorExprSyntax.self),
           rangeOperator.operator.text == "..<" {
            return (infix.leftOperand, infix.rightOperand)
        }

        return nil
    }
}

// MARK: - The property

extension BitFieldMacro {
    /// The property the macro is attached to, once it is known to be one the
    /// macro can give a getter.
    struct Field {
        let binding: PatternBindingSyntax
        let type: TypeSyntax

        init?(reading property: VariableDeclSyntax, in context: some MacroExpansionContext) {
            if property.bindingSpecifier.tokenKind == .keyword(.let) {
                context.diagnose(Diagnostic(
                    node: property.bindingSpecifier,
                    message: MacroExpansionErrorMessage(
                        "a bit field is computed from 'rawValue', so it is declared with 'var'"
                    ),
                    fixIt: .replace(
                        message: MacroExpansionFixItMessage("replace 'let' with 'var'"),
                        oldNode: property.bindingSpecifier,
                        newNode: property.bindingSpecifier.with(\.tokenKind, .keyword(.var))
                    )
                ))
                return nil
            }

            if let staticModifier = property.modifiers.first(where: { modifier in
                modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
            }) {
                context[.error, staticModifier] =
                    "a bit field reads the 'rawValue' of an instance, so it cannot be '\(staticModifier.name.text)'"
                return nil
            }

            // A declaration of several variables never reaches the macro: the
            // macro system reports that an accessor macro applies to a single
            // variable.
            guard property.bindings.count == 1, let binding = property.bindings.first else {
                return nil
            }

            guard binding.pattern.is(IdentifierPatternSyntax.self) else {
                context[.error, binding.pattern] = "'@BitField' needs a property name, not a pattern"
                return nil
            }

            // Observers count too: the compiler drops `willSet` / `didSet` once
            // a macro adds a getter. The compiler reports this on the property's
            // name (measured); swift-macro-testing draws it elsewhere, because
            // swift-syntax expands the macro on a rewritten copy of a declaration
            // with accessors, one that no longer sits in the file.
            if binding.accessorBlock != nil {
                context[.error, binding.pattern] = "'@BitField' writes the getter itself; remove this property's accessors"
                return nil
            }

            guard let typeAnnotation = binding.typeAnnotation else {
                context[.error, binding.pattern] =
                    "'@BitField' needs the property's type written out: the type decides how the bits are read"
                return nil
            }

            if let initializer = binding.initializer {
                let bindingWithoutInitializer = binding
                    .with(\.initializer, nil)
                    .with(\.typeAnnotation, typeAnnotation.with(\.trailingTrivia, initializer.trailingTrivia))
                context.diagnose(Diagnostic(
                    node: initializer,
                    message: MacroExpansionErrorMessage(
                        "a bit field has no storage of its own; its value is read from 'rawValue'"
                    ),
                    fixIt: .replace(
                        message: MacroExpansionFixItMessage("remove the initial value"),
                        oldNode: binding,
                        newNode: bindingWithoutInitializer
                    )
                ))
                return nil
            }

            self.binding = binding
            self.type = typeAnnotation.type.trimmed
        }
    }
}

extension BitFieldMacro.Field {
    /// Why `bits` cannot hold a value of the property's type, when that shows
    /// in the spelling of the type. A typealias or a generic parameter is not
    /// checked here; the runtime checks widths it cannot see.
    func mismatch(with bits: BitFieldMacro.BitRange) -> String? {
        let spelling = type.standardLibrarySpelling

        if spelling == "Bool", bits.width != 1 {
            return "a 'Bool' bit field reads one bit, but bits \(bits) are \(bits.width) bits wide"
        }

        if let integerBitWidth = Self.integerBitWidths[spelling], bits.width > integerBitWidth {
            return "bits \(bits) are \(bits.width) bits wide, more than '\(type.trimmedDescription)' holds"
        }

        return nil
    }

    /// The width of each standard library integer type. `Int` and `UInt` are
    /// 64 bits everywhere but arm64_32 watchOS, where they are 32; a macro
    /// cannot know which platform the caller builds for, so the wider width is
    /// checked, as `@FlagSet` does.
    private static let integerBitWidths: [String: Int] = [
        "Int": 64, "UInt": 64,
        "Int8": 8, "UInt8": 8,
        "Int16": 16, "UInt16": 16,
        "Int32": 32, "UInt32": 32,
        "Int64": 64, "UInt64": 64,
        "Int128": 128, "UInt128": 128,
    ]

    func getter(
        reading configuration: BitFieldMacro.Configuration,
        in context: some MacroExpansionContext
    ) -> AccessorDeclSyntax {
        let bits = configuration.bits
        var arguments = "of: self.rawValue, bits: \(bits.lowerBound)..<\(bits.upperBound), as: (\(type.trimmedDescription)).self"
        if let defaultValue = configuration.defaultValue {
            arguments += ", default: \(defaultValue.trimmedDescription)"
        }
        // Module-qualified, so that a member of the caller's type with the same
        // name cannot capture the call.
        let call = "SwiftStdlibToolbox._BitFieldAccess.value(\(arguments))"

        // A type no conversion fits is an error on this call, which the caller
        // never wrote. Mapping the call to the property's own line reports it
        // there. The directive sets the line of the line after it, so the call
        // stands alone between the two.
        let body: String
        if let location = context.location(of: binding.pattern, at: .afterLeadingTrivia, filePathMode: .filePath) {
            body = """
            #sourceLocation(file: \(location.file), line: \(location.line))
            \(call)
            #sourceLocation()
            """
        } else {
            body = call
        }

        return """
        get {
        \(raw: body)
        }
        """
    }
}

// MARK: - Syntax helpers

extension TypeSyntax {
    /// The type as written, without a leading `Swift.` — so that `Swift.Bool`
    /// is recognized as `Bool`.
    fileprivate var standardLibrarySpelling: String {
        let spelling = trimmedDescription
        let qualifier = "Swift."
        return spelling.hasPrefix(qualifier) ? String(spelling.dropFirst(qualifier.count)) : spelling
    }
}
