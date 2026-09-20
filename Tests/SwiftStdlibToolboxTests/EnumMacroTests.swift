import Testing

@testable import SwiftStdlibToolbox

/// Behaviour of the five enumeration macros.
///
/// These are runtime assertions, but they double as the compile-time guard on
/// the expansions: every fixture below has to compile before a single
/// assertion runs, which is what catches an expansion that is merely
/// *plausible* rather than valid. Expansion shape is pinned separately, in
/// `Tests/SwiftStdlibToolboxMacroTests/`.
@Suite("Enum macros")
struct EnumMacroTests {

    // MARK: - @Bijection

    @Test("Bijection inverts a mapping generic over the value type")
    func bijectionInvertsGenericMapping() {
        for light in TrafficLight.allCases {
            #expect(TrafficLight(light.description[...]) == light)
        }
    }

    @Test("Bijection inverts a mapping over a concrete value type")
    func bijectionInvertsConcreteMapping() {
        for light in TrafficLight.allCases {
            #expect(TrafficLight(light.symbol) == light)
        }
    }

    @Test("Bijection honours a custom argument label")
    func bijectionHonoursArgumentLabel() {
        for light in TrafficLight.allCases {
            #expect(TrafficLight(code: light.code) == light)
        }
    }

    @Test("Bijection inverts a mapping onto a tuple")
    func bijectionInvertsTupleMapping() {
        for light in TrafficLight.allCases {
            #expect(TrafficLight(bytes: light.bytes) == light)
        }
    }

    @Test("Bijection returns nil for a value outside the mapping")
    func bijectionRejectsUnmappedValue() {
        #expect(TrafficLight(code: 99) == nil)
        #expect(TrafficLight("chartreuse"[...]) == nil)
    }

    // MARK: - @CaseTag

    @Test("CaseTag maps every case to its tag")
    func caseTagMapsEveryCase() {
        #expect(Action.start.tag == .start)
        #expect(Action.stop.tag == .stop)
        #expect(Action.reset(89).tag == .reset)
        #expect(Action.reset(nil).tag == .reset)
    }

    @Test("CaseTag backs the tag with a string raw value")
    func caseTagBacksWithString() {
        #expect(BackedByStringTag.first.rawValue == "first")
        #expect(BackedByStringTag.second.rawValue == "second")
    }

    @Test("CaseTag backs the tag with an integer raw value")
    func caseTagBacksWithInteger() {
        #expect(BackedByIntegerTag.a.rawValue == 0)
        #expect(BackedByIntegerTag.b.rawValue == 1)
        #expect(BackedByIntegerTag.c.rawValue == 2)
    }

    @Test("CaseTag drops indirect from the tag it generates")
    func caseTagDropsIndirect() {
        #expect(Tree.leaf.tag == .leaf)
        #expect(Tree.node(.leaf).tag == .node)
    }

    // MARK: - @MirroredCases

    @Test("MirroredCases mirrors the only annotated nested enum")
    func mirroredCasesMirrorsSolitaryNestedEnum() {
        let first: Solitary.Union = .first
        let second: Solitary.Union = .second(42)

        #expect(first.tag == .first)
        #expect(second.tag == .second)
    }

    @Test("MirroredCases ignores nested enums that are not annotated")
    func mirroredCasesIgnoresUnannotatedNestedEnums() {
        let first: WithUnrelated.Target = .first
        let second: WithUnrelated.Target = .second("abc")

        #expect(first.tag == .first)
        #expect(second.tag == .second)
    }

    @Test("MirroredCases works with a raw-backed host")
    func mirroredCasesWorksWithRawBackedHost() {
        let one: RawBacked.Union = .one(1)
        let two: RawBacked.Union = .two("2")

        #expect(one.tag == .one)
        #expect(two.tag == .two)
        #expect(RawBacked.one.rawValue == "one")
        #expect(RawBacked.two.rawValue == "two")
    }

    // MARK: - @DefaultedCases

    @Test("DefaultedCases fills a lone optional payload with nil")
    func defaultedCasesFillsLoneOptional() {
        #expect(Simple.reset == .reset(nil))
    }

    @Test("DefaultedCases fills labelled and multi-parameter cases")
    func defaultedCasesFillsLabelledCases() {
        #expect(Labeled.single == .single(value: nil))
        #expect(Labeled.multi == .multi(first: nil, second: nil))
    }

    @Test("DefaultedCases works on an indirect enum")
    func defaultedCasesWorksOnIndirectEnum() {
        let node: Branch = .node
        #expect(node == .node(nil))
    }

    @Test("DefaultedCases prefers a default argument over nil")
    func defaultedCasesPrefersDefaultArgument() {
        #expect(Defaulted.default == .default(count: 10))
        #expect(Defaulted.optionalWithValue == .optionalWithValue("guest"))
        #expect(Defaulted.optionalWithNil == .optionalWithNil(tag: nil))
        #expect(Defaulted.optionalWithout == .optionalWithout(status: nil))
        #expect(Defaulted.multiple == .multiple(x: 1, y: "hello", z: nil))
        #expect(Defaulted.unlabeled == .unlabeled(89))
    }

    // MARK: - @Projection

    @Test("Projection unwraps optional payloads")
    func projectionUnwrapsOptionalPayloads() {
        #expect(Single.click(123).id == "123")
        #expect(Single.hover("area").id == "area")
        #expect(Single.click(nil).id == nil)
        #expect(Single.hover(nil).id == nil)
        #expect(Single.scroll.id == nil)
    }

    @Test("Projection passes a non-optional payload through untouched")
    func projectionPassesNonOptionalPayload() {
        #expect(NonOptional.click(89).id == "89")
        #expect(NonOptional.hover("hovering").id == "hovering")
        #expect(NonOptional.hover(nil).id == nil)
        #expect(NonOptional.scroll.id == nil)
    }

    @Test("Projection can be applied more than once")
    func projectionAppliesMoreThanOnce() {
        #expect(Multi.text("hello").owner == "hello")
        #expect(Multi.text("hello").count == 5)
        #expect(Multi.numbers([1, 2, 3]).count == 3)
        #expect(Multi.text(nil).owner == nil)
        #expect(Multi.none.count == nil)
    }

    @Test("Projection flattens an optional return type by default")
    func projectionFlattensOptionalReturn() {
        let present: String? = Flattened.item(89).tag
        let absent: String? = Flattened.other("").tag

        #expect(present == "89")
        #expect(absent == nil)
        #expect(Flattened.plain.tag == nil)
    }

    @Test("Projection keeps the double optional when flattening is off")
    func projectionKeepsDoubleOptional() {
        let present: String?? = Unflattened.item(89).tag
        let emptyDescription: String?? = Unflattened.other("").tag

        #expect(present == .some(.some("89")))
        #expect(emptyDescription == .some(nil))
        #expect(Unflattened.plain.tag == nil)
    }

    @Test("Projection looks through parentheses around a payload type")
    func projectionLooksThroughParentheses() {
        let item: String? = Parenthesized.item(89).tag
        let other: String? = Parenthesized.other("test").tag

        #expect(item == "89")
        #expect(other == "test")
        #expect(Parenthesized.plain.tag == nil)
    }

    @Test("Projection handles a case carrying several values")
    func projectionHandlesSeveralValues() {
        #expect(Coordinate.point(1, 2).pair == "1,2")
        #expect(Coordinate.offset(x: 3, y: 4).pair == "3,4")
    }

    @Test("Projection skips cases whose value count does not match")
    func projectionSkipsMismatchedValueCount() {
        #expect(Coordinate.single(1).pair == nil)
        #expect(Coordinate.origin.pair == nil)
    }

    @Test("Projection takes argument labels from the projection function")
    func projectionTakesLabelsFromProjectionFunction() {
        #expect(Labelled.both("id", 7).combine == "id#7")
        #expect(Labelled.neither.combine == nil)
    }

    @Test("Projection unwraps each optional value independently")
    func projectionUnwrapsEachValueIndependently() {
        #expect(MixedOptional.values(1, 2).pair == "1,2")
        #expect(MixedOptional.values(nil, 2).pair == nil)
    }

    @Test("Projection matches cases carrying nothing against a zero-argument function")
    func projectionMatchesValuelessCases() {
        #expect(Placeholder.first.placeholder == "none")
        #expect(Placeholder.second.placeholder == "none")
        #expect(Placeholder.carrying(1).placeholder == nil)
    }

    @Test("Projection covering every case still yields an optional")
    func projectionCoveringEveryCaseYieldsOptional() {
        // The property type stays optional even though the switch is now
        // exhaustive — deliberately, so that adding a case later cannot change
        // the type at every call site.
        let first: String? = FullyCovered.first("a").label
        #expect(first == "a")
        #expect(FullyCovered.second(2).label == "2")
    }
}

// MARK: - Fixtures: @Bijection

extension EnumMacroTests {
    enum TrafficLight: CaseIterable, Equatable {
        case green, amber, red

        /// Generic over `StringProtocol`, so a `Substring` needs no copy at
        /// the call site. This is also the only spelling that emits `copy`.
        @Bijection(where: "StringProtocol") var description: String {
            switch self {
            case .green: "green"
            case .amber: "amber"
            case .red: "red"
            }
        }

        @Bijection var symbol: Unicode.Scalar {
            switch self {
            case .green: "g"
            case .amber: "a"
            case .red: "r"
            }
        }

        /// Spelled with an explicit `get`, the other accepted accessor shape.
        @Bijection(label: "code") var code: Int {
            get {
                switch self {
                case .green: 1
                case .amber: 2
                case .red: 3
                }
            }
        }

        /// A tuple value type is the case that must *not* be given `copy`.
        @Bijection(label: "bytes") var bytes: (UInt8, UInt8) {
            switch self {
            case .green: (0, 1)
            case .amber: (0, 2)
            case .red: (0, 3)
            }
        }
    }
}

// MARK: - Fixtures: @CaseTag

extension EnumMacroTests {
    @CaseTag enum Action: Equatable {
        case start
        case stop
        case reset(Int?)
    }

    @CaseTag(backing: String.self) enum BackedByString {
        case first
        case second(Int)
    }

    @CaseTag(backing: Int.self) enum BackedByInteger {
        case a
        case b
        case c
    }

    @CaseTag indirect enum Tree {
        case leaf
        case node(Tree)
    }
}

// MARK: - Fixtures: @MirroredCases

extension EnumMacroTests {
    @MirroredCases enum Solitary: Equatable {
        @CaseTag(by: Solitary.self) enum Union: Equatable {
            case first
            case second(Int)
        }
    }

    @MirroredCases enum WithUnrelated: Equatable {
        enum Unrelated {}

        @CaseTag(by: WithUnrelated.self) enum Target: Equatable {
            case first
            case second(String)
        }
    }

    @MirroredCases enum RawBacked: String, Equatable {
        @CaseTag(by: RawBacked.self) enum Union: Equatable {
            case one(Int)
            case two(String)
        }
    }
}

// MARK: - Fixtures: @DefaultedCases

extension EnumMacroTests {
    @DefaultedCases enum Simple: Equatable {
        case reset(Int?)
        case start
        case stop
    }

    @DefaultedCases enum Labeled: Equatable {
        case single(value: Int?)
        case multi(first: Int?, second: String?)
        case plain
    }

    @DefaultedCases indirect enum Branch: Equatable {
        case leaf
        case node(Branch?)
    }

    @DefaultedCases enum Defaulted: Equatable {
        // Neither optional nor defaulted: nothing to fill these with, so no
        // constructor is generated for them.
        case skippedNonOptional(Int)
        case skippedMixed(x: Int, y: String? = "default")

        case `default`(count: Int = 10)
        case optionalWithValue(String? = "guest")
        case optionalWithNil(tag: String? = nil)
        case optionalWithout(status: Bool?)
        case multiple(x: Int = 1, y: String? = "hello", z: Double?)
        case unlabeled(Int = 89)
    }
}

// MARK: - Fixtures: @Projection

extension EnumMacroTests {
    @Projection enum Single: Equatable {
        case click(Int?)
        case hover(String?)
        case scroll

        @ProjectionFunction
        static func id(_ value: some CustomStringConvertible) -> String {
            value.description
        }
    }

    @Projection enum NonOptional: Equatable {
        case click(Int)
        case hover(String?)
        case scroll

        @ProjectionFunction
        static func id(_ value: some CustomStringConvertible) -> String {
            value.description
        }
    }

    /// Two marked functions, one `@Projection` — where the old spelling needed
    /// the attribute repeated per projection.
    @Projection enum Multi: Equatable {
        case text(String?)
        case numbers([Int]?)
        case none

        @ProjectionFunction
        static func owner(_ value: some CustomStringConvertible) -> String {
            value.description
        }

        @ProjectionFunction
        static func count(_ value: some Collection) -> Int {
            value.count
        }
    }

    @Projection enum Flattened: Equatable {
        case item(Int?)
        case other(String?)
        case plain

        @ProjectionFunction
        static func tag(_ value: some CustomStringConvertible) -> String? {
            let description = value.description
            return description.isEmpty ? nil : description
        }
    }

    @Projection enum Unflattened: Equatable {
        case item(Int?)
        case other(String?)
        case plain

        @ProjectionFunction(flatten: false)
        static func tag(_ value: some CustomStringConvertible) -> String? {
            let description = value.description
            return description.isEmpty ? nil : description
        }
    }

    @Projection enum Parenthesized {
        case item((Int?))
        case other((String)?)
        case plain

        @ProjectionFunction
        static func tag(_ value: some CustomStringConvertible) -> (String?) {
            let description = value.description
            return description.isEmpty ? nil : description
        }
    }
}

// MARK: - Fixtures: @Projection over several values

extension EnumMacroTests {
    @Projection enum Coordinate: Equatable {
        case point(Int, Int)
        case offset(x: Int, y: Int)
        case single(Int)
        case origin

        @ProjectionFunction
        static func pair(_ first: Int, _ second: Int) -> String {
            "\(first),\(second)"
        }
    }

    @Projection enum Labelled: Equatable {
        case both(String, Int)
        case neither

        @ProjectionFunction
        static func combine(text: String, number: Int) -> String {
            "\(text)#\(number)"
        }
    }

    @Projection enum MixedOptional: Equatable {
        case values(Int?, Int)
        case nothing

        @ProjectionFunction
        static func pair(_ first: Int, _ second: Int) -> String {
            "\(first),\(second)"
        }
    }

    @Projection enum Placeholder: Equatable {
        case first
        case second
        case carrying(Int)

        @ProjectionFunction
        static func placeholder() -> String {
            "none"
        }
    }

    /// Every case is projectable and none needs optional unwrapping, so the
    /// generated `switch` is exhaustive and must carry no `default`.
    @Projection enum FullyCovered: Equatable {
        case first(String)
        case second(Int)

        @ProjectionFunction
        static func label(_ value: some CustomStringConvertible) -> String {
            value.description
        }
    }
}
