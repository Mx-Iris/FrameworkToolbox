import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "Bijection": BijectionMacro.self,
    "CaseTag": CaseTagMacro.self,
    "MirroredCases": MirroredCasesMacro.self,
    "DefaultedCases": DefaultedCasesMacro.self,
    "Projection": ProjectionMacro.self,
    "ProjectionFunction": ProjectionFunctionMacro.self,
]))
struct EnumMacroExpansionTests {

    // MARK: - @Bijection

    @Test func bijectionInvertsSwitchMapping() {
        assertMacro {
            """
            enum Enumeration {
                @Bijection var value: Unicode.Scalar {
                    switch self {
                    case .a: "a"
                    case .b: "b"
                    }
                }
            }
            """
        } expansion: {
            """
            enum Enumeration {
                var value: Unicode.Scalar {
                    switch self {
                    case .a: "a"
                    case .b: "b"
                    }
                }

                init?(_ $value: borrowing Unicode.Scalar) {
                    switch $value {
                    case "a":
                        self = .a
                    case "b":
                        self = .b
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }

    @Test func bijectionHonoursArgumentLabel() {
        assertMacro {
            """
            enum Enumeration {
                @Bijection(label: "index") var index: Int {
                    get {
                        switch self {
                        case .a: 1
                        case .b: 2
                        }
                    }
                }
            }
            """
        } expansion: {
            """
            enum Enumeration {
                var index: Int {
                    get {
                        switch self {
                        case .a: 1
                        case .b: 2
                        }
                    }
                }

                init?(index $value: borrowing Int) {
                    switch $value {
                    case 1:
                        self = .a
                    case 2:
                        self = .b
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }

    @Test func bijectionEmitsCopyOnlyForGenericConstraint() {
        assertMacro {
            """
            enum Enumeration {
                @Bijection(where: "StringProtocol") public var description: String {
                    switch self {
                    case .a: "a"
                    }
                }
            }
            """
        } expansion: {
            """
            enum Enumeration {
                public var description: String {
                    switch self {
                    case .a: "a"
                    }
                }

                public init?(_ $value: borrowing some StringProtocol) {
                    switch copy $value {
                    case "a":
                        self = .a
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }

    @Test func bijectionMirrorsInlinableAndAvailability() {
        assertMacro {
            """
            enum Enumeration {
                @Bijection
                @available(macOS 13, *)
                @inlinable
                public var value: Int {
                    switch self {
                    case .a: 1
                    }
                }
            }
            """
        } expansion: {
            """
            enum Enumeration {
                @available(macOS 13, *)
                @inlinable
                public var value: Int {
                    switch self {
                    case .a: 1
                    }
                }

                @available(macOS 13, *)
                    @inlinable
                    public init?(_ $value: borrowing Int) {
                    switch $value {
                    case 1:
                        self = .a
                    default:
                        return nil
                    }
                }
            }
            """
        }
    }

    @Test func bijectionRejectsStoredProperty() {
        assertMacro {
            """
            enum Enumeration {
                @Bijection var value: Int = 1
            }
            """
        } diagnostics: {
            """
            enum Enumeration {
                @Bijection var value: Int = 1
                ┬─────────
                ╰─ 🛑 '@Bijection' must be applied to a computed property
            }
            """
        }
    }

    // MARK: - @CaseTag

    @Test func caseTagGeneratesPeerAndProperty() {
        assertMacro {
            """
            @CaseTag enum Action {
                case start
                case reset(Int?)
            }
            """
        } expansion: {
            """
            enum Action {
                case start
                case reset(Int?)

                var tag: ActionTag {
                    switch self {
                    case .start:
                        .start
                    case .reset:
                        .reset
                    }
                }
            }

            enum ActionTag {
                case start
                case reset

            }
            """
        }
    }

    @Test func caseTagBacksPeerWithRawValueType() {
        assertMacro {
            """
            @CaseTag(backing: String.self) public enum Action {
                case start
                case reset(Int?)
            }
            """
        } expansion: {
            """
            public enum Action {
                case start
                case reset(Int?)

                @inlinable public var tag: ActionTag {
                    switch self {
                    case .start:
                        .start
                    case .reset:
                        .reset
                    }
                }
            }

            public enum ActionTag: String {
                case start
                case reset

            }
            """
        }
    }

    @Test func caseTagDropsIndirectFromGeneratedDeclarations() {
        assertMacro {
            """
            @CaseTag indirect enum Tree {
                case leaf
                case node(Tree)
            }
            """
        } expansion: {
            """
            indirect enum Tree {
                case leaf
                case node(Tree)

                var tag: TreeTag {
                    switch self {
                    case .leaf:
                        .leaf
                    case .node:
                        .node
                    }
                }
            }

            enum TreeTag {
                case leaf
                case node

            }
            """
        }
    }

    @Test func caseTagGeneratesNoPeerWhenPointedAtAnExistingTag() {
        assertMacro {
            """
            @CaseTag(by: Tooltip.self) enum Union {
                case text(String)
                case icon(Int)
            }
            """
        } expansion: {
            """
            enum Union {
                case text(String)
                case icon(Int)

                var tag: Tooltip {
                    switch self {
                    case .text:
                        .text
                    case .icon:
                        .icon
                    }
                }
            }
            """
        }
    }

    @Test func caseTagRejectsNonEnumeration() {
        assertMacro {
            """
            @CaseTag struct NotAnEnumeration {}
            """
        } diagnostics: {
            """
            @CaseTag struct NotAnEnumeration {}
            ┬──────────────────────────────────
            ╰─ 🛑 '@CaseTag' must be applied to an enum
            """
        }
    }

    // MARK: - @MirroredCases

    @Test func mirroredCasesCopiesNestedCaseNames() {
        assertMacro {
            """
            @MirroredCases public enum Tooltip {
                @CaseTag(by: Tooltip.self) public enum Union {
                    case text(String)
                    case icon(Int)
                    case custom
                }
            }
            """
        } expansion: {
            """
            public enum Tooltip {
                public enum Union {
                    case text(String)
                    case icon(Int)
                    case custom

                    @inlinable public var tag: Tooltip {
                        switch self {
                        case .text:
                            .text
                        case .icon:
                            .icon
                        case .custom:
                            .custom
                        }
                    }
                }

                case text

                case icon

                case custom
            }
            """
        }
    }

    @Test func mirroredCasesRequiresAnAnnotatedNestedEnumeration() {
        assertMacro {
            """
            @MirroredCases enum Tooltip {
                enum Union {
                    case text(String)
                }
            }
            """
        } diagnostics: {
            """
            @MirroredCases enum Tooltip {
            ╰─ 🛑 '@MirroredCases' requires a nested enum annotated with '@CaseTag'
                enum Union {
                    case text(String)
                }
            }
            """
        }
    }

    @Test func mirroredCasesRejectsTwoAnnotatedNestedEnumerations() {
        assertMacro {
            """
            @MirroredCases enum Tooltip {
                @CaseTag(by: Tooltip.self) enum First {
                    case text(String)
                }
                @CaseTag(by: Tooltip.self) enum Second {
                    case icon(Int)
                }
            }
            """
        } diagnostics: {
            """
            @MirroredCases enum Tooltip {
            ╰─ 🛑 '@MirroredCases' found multiple nested enums annotated with '@CaseTag'
                @CaseTag(by: Tooltip.self) enum First {
                    case text(String)
                }
                @CaseTag(by: Tooltip.self) enum Second {
                    case icon(Int)
                }
            }
            """
        }
    }

    @Test func mirroredCasesRejectsATagPointingElsewhere() {
        assertMacro {
            """
            @MirroredCases enum Tooltip {
                @CaseTag(by: Elsewhere.self) enum Union {
                    case text(String)
                }
            }
            """
        } diagnostics: {
            """
            @MirroredCases enum Tooltip {
                @CaseTag(by: Elsewhere.self) enum Union {
                ┬───────────────────────────
                ╰─ 🛑 '@CaseTag' must specify 'by: Tooltip.self'
                    case text(String)
                }
            }
            """
        }
    }

    // MARK: - @DefaultedCases

    @Test func defaultedCasesFillsOptionalsAndDefaults() {
        assertMacro {
            """
            @DefaultedCases enum Task {
                case recurring(interval: Int = 60, tag: String? = nil)
                case quick
                case custom(deadline: Date)
                case unlabeled(Int?)
            }
            """
        } expansion: {
            """
            enum Task {
                case recurring(interval: Int = 60, tag: String? = nil)
                case quick
                case custom(deadline: Date)
                case unlabeled(Int?)

                static var recurring: Self {
                    .recurring(interval: 60, tag: nil)
                }

                static var unlabeled: Self {
                    .unlabeled(nil)
                }
            }
            """
        }
    }

    @Test func defaultedCasesWarnsAboutUnsugaredOptional() {
        assertMacro {
            """
            @DefaultedCases enum Task {
                case unsugared(Optional<Int>)
            }
            """
        } diagnostics: {
            """
            @DefaultedCases enum Task {
                case unsugared(Optional<Int>)
                               ┬────────────
                               ╰─ ⚠️ spelling 'Optional<Int>' will not be recognized here; use the sugared optional '?' instead
            }
            """
        } expansion: {
            """
            enum Task {
                case unsugared(Optional<Int>)
            }
            """
        }
    }

    // MARK: - @Projection

    @Test func projectionUnwrapsOptionalPayloads() {
        assertMacro {
            """
            @Projection enum Target {
                case user(User)
                case session(Session?)
                case anonymous

                @ProjectionFunction
                static func id(_ value: some Identifiable<String>) -> String {
                    value.id
                }
            }
            """
        } expansion: {
            """
            enum Target {
                case user(User)
                case session(Session?)
                case anonymous
                static func id(_ value: some Identifiable<String>) -> String {
                    value.id
                }

                var id: String? {
                    switch self {
                    case .user(let payload):
                        Self.id(payload)
                    case .session(let payload?):
                        Self.id(payload)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionGeneratesOnePropertyPerMarkedFunction() {
        assertMacro {
            """
            @Projection enum Target {
                case text(String?)
                case none

                @ProjectionFunction
                static func owner(_ value: some CustomStringConvertible) -> String {
                    value.description
                }

                @ProjectionFunction
                static func length(_ value: some Collection) -> Int {
                    value.count
                }
            }
            """
        } expansion: {
            """
            enum Target {
                case text(String?)
                case none
                static func owner(_ value: some CustomStringConvertible) -> String {
                    value.description
                }
                static func length(_ value: some Collection) -> Int {
                    value.count
                }

                var owner: String? {
                    switch self {
                    case .text(let payload?):
                        Self.owner(payload)
                    default:
                        nil
                    }
                }

                var length: Int? {
                    switch self {
                    case .text(let payload?):
                        Self.length(payload)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionIgnoresUnmarkedStaticFunctions() {
        assertMacro {
            """
            @Projection enum Target {
                case item(Int?)

                @ProjectionFunction
                static func tag(_ value: some CustomStringConvertible) -> String {
                    value.description
                }

                static func helper(_ value: Int) -> String {
                    "helper"
                }
            }
            """
        } expansion: {
            """
            enum Target {
                case item(Int?)
                static func tag(_ value: some CustomStringConvertible) -> String {
                    value.description
                }

                static func helper(_ value: Int) -> String {
                    "helper"
                }

                var tag: String? {
                    switch self {
                    case .item(let payload?):
                        Self.tag(payload)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionFlattensOptionalReturnType() {
        assertMacro {
            """
            @Projection enum Target {
                case item(Int?)

                @ProjectionFunction
                static func tag(_ value: some CustomStringConvertible) -> String? {
                    value.description
                }
            }
            """
        } expansion: {
            """
            enum Target {
                case item(Int?)
                static func tag(_ value: some CustomStringConvertible) -> String? {
                    value.description
                }

                var tag: String? {
                    switch self {
                    case .item(let payload?):
                        Self.tag(payload)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionKeepsDoubleOptionalWhenFlatteningIsOff() {
        assertMacro {
            """
            @Projection enum Target {
                case item(Int?)

                @ProjectionFunction(flatten: false)
                static func tag(_ value: some CustomStringConvertible) -> String? {
                    value.description
                }
            }
            """
        } expansion: {
            """
            enum Target {
                case item(Int?)
                static func tag(_ value: some CustomStringConvertible) -> String? {
                    value.description
                }

                var tag: String?? {
                    switch self {
                    case .item(let payload?):
                        Self.tag(payload)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionDestructuresSeveralValues() {
        assertMacro {
            """
            @Projection enum Coordinate {
                case point(Int, Int)
                case single(Int)
                case origin

                @ProjectionFunction
                static func pair(_ first: Int, _ second: Int) -> String {
                    "joined"
                }
            }
            """
        } expansion: {
            """
            enum Coordinate {
                case point(Int, Int)
                case single(Int)
                case origin
                static func pair(_ first: Int, _ second: Int) -> String {
                    "joined"
                }

                var pair: String? {
                    switch self {
                    case .point(let payload1, let payload2):
                        Self.pair(payload1, payload2)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionTakesArgumentLabelsFromTheProjectionFunction() {
        assertMacro {
            """
            @Projection enum Labelled {
                case both(String, Int)
                case neither

                @ProjectionFunction
                static func combine(text: String, number: Int) -> String {
                    text
                }
            }
            """
        } expansion: {
            """
            enum Labelled {
                case both(String, Int)
                case neither
                static func combine(text: String, number: Int) -> String {
                    text
                }

                var combine: String? {
                    switch self {
                    case .both(let payload1, let payload2):
                        Self.combine(text: payload1, number: payload2)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionMatchesValuelessCasesAgainstAZeroArgumentFunction() {
        assertMacro {
            """
            @Projection enum Placeholder {
                case first
                case carrying(Int)

                @ProjectionFunction
                static func placeholder() -> String {
                    "none"
                }
            }
            """
        } expansion: {
            """
            enum Placeholder {
                case first
                case carrying(Int)
                static func placeholder() -> String {
                    "none"
                }

                var placeholder: String? {
                    switch self {
                    case .first:
                        Self.placeholder()
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionOmitsDefaultWhenEveryCaseIsCovered() {
        assertMacro {
            """
            @Projection enum FullyCovered {
                case first(String)
                case second(Int)

                @ProjectionFunction
                static func label(_ value: some CustomStringConvertible) -> String {
                    value.description
                }
            }
            """
        } expansion: {
            """
            enum FullyCovered {
                case first(String)
                case second(Int)
                static func label(_ value: some CustomStringConvertible) -> String {
                    value.description
                }

                var label: String? {
                    switch self {
                    case .first(let payload):
                        Self.label(payload)
                    case .second(let payload):
                        Self.label(payload)
                    }
                }
            }
            """
        }
    }

    @Test func projectionKeepsDefaultWhenAnOptionalPayloadIsUnwrapped() {
        assertMacro {
            """
            @Projection enum PartiallyCovered {
                case first(String?)

                @ProjectionFunction
                static func label(_ value: some CustomStringConvertible) -> String {
                    value.description
                }
            }
            """
        } expansion: {
            """
            enum PartiallyCovered {
                case first(String?)
                static func label(_ value: some CustomStringConvertible) -> String {
                    value.description
                }

                var label: String? {
                    switch self {
                    case .first(let payload?):
                        Self.label(payload)
                    default:
                        nil
                    }
                }
            }
            """
        }
    }

    @Test func projectionRequiresAtLeastOneMarkedFunction() {
        assertMacro {
            """
            @Projection enum Target {
                case user(User)

                static func id(_ value: User) -> String {
                    "unmarked"
                }
            }
            """
        } diagnostics: {
            """
            @Projection enum Target {
            ┬──────────
            ╰─ 🛑 enum 'Target' must declare at least one static function marked with '@ProjectionFunction' for '@Projection' to build a property from
                case user(User)

                static func id(_ value: User) -> String {
                    "unmarked"
                }
            }
            """
        }
    }

    // MARK: - @ProjectionFunction

    @Test func projectionFunctionRejectsInstanceMethod() {
        assertMacro {
            """
            enum Target {
                @ProjectionFunction
                func id(_ value: Int) -> String {
                    "instance"
                }
            }
            """
        } diagnostics: {
            """
            enum Target {
                @ProjectionFunction
                func id(_ value: Int) -> String {
                     ┬─
                     ╰─ 🛑 '@ProjectionFunction' must be applied to a static function — '@Projection' calls it as 'Self.id(…)'
                    "instance"
                }
            }
            """
        }
    }

    @Test func projectionFunctionRejectsMissingReturnType() {
        assertMacro {
            """
            enum Target {
                @ProjectionFunction
                static func id(_ value: Int) {
                }
            }
            """
        } diagnostics: {
            """
            enum Target {
                @ProjectionFunction
                static func id(_ value: Int) {
                            ┬─
                            ╰─ 🛑 a projection function must have a return type
                }
            }
            """
        }
    }
}
