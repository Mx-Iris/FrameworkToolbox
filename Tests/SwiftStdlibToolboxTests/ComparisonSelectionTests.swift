import Testing
@testable import SwiftStdlibToolbox

// MARK: - Fixtures

/// Three definitions that produce three different orderings over the same
/// fixture, so a test asserting one cannot accidentally pass under another.
/// Conforms to `FrameworkToolboxCompatible` as well, because the two-value
/// `compare(to:using:)` is reached through the element's own `.box`. The
/// sequence methods need no such conformance — there the `.box` is the array's.
private struct Employee: ComparableBuildable, FrameworkToolboxCompatible {
    var name: String
    var department: String
    var salary: Int

    static var comparableDefinition: some ComparisonStep<Self> {
        compare(\.name)
    }

    @ComparableBuilder<Self>
    static var bySalaryDescending: some ComparisonStep<Self> {
        compareDescending(\.salary)
        compare(\.name)
    }

    @ComparableBuilder<Self>
    static var byDepartmentThenName: some ComparisonStep<Self> {
        compare(\.department)
        compare(\.name)
    }
}

/// The declaration order here is load-bearing: it differs from the result of
/// every definition below, so a method that silently does nothing cannot pass by
/// returning its input unchanged.
///
///     declared              alice, carol, bob
///     comparableDefinition  alice, bob, carol
///     bySalaryDescending    carol, alice, bob
///     byDepartmentThenName  bob, carol, alice
private let staff = [
    Employee(name: "alice", department: "sales", salary: 70),
    Employee(name: "carol", department: "engineering", salary: 90),
    Employee(name: "bob", department: "engineering", salary: 70),
]

private let carol = Employee(name: "carol", department: "engineering", salary: 90)
private let alice = Employee(name: "alice", department: "sales", salary: 70)

/// Deliberately conforms to nothing: a definition needs no `ComparableBuildable`
/// conformance, only a static property whose type is a `ComparisonStep` over it.
/// The steps are written as bare key paths, which is what the builder's
/// `buildExpression` overloads exist for — `compare(_:)` is unreachable here.
private struct SensorReading {
    var timestamp: Int
    var celsius: Double
    var note: String?

    @ComparableBuilder<Self>
    static var byTimestampThenCelsiusDescending: some ComparisonStep<Self> {
        \.timestamp
        DescendingKeyPathComparisonStep(\Self.celsius)
        \.note
    }
}

/// For stability checks: `identifier` is never compared, so its order in the
/// output is only ever the order the sort preserved.
private struct Ticket {
    var priority: Int
    var identifier: Int
}

// MARK: - Selecting a definition

@Suite("Comparison definition selection")
struct ComparisonDefinitionSelectionTests {

    @Test("sorted(using:) follows the selected definition, not the default one")
    func sortedUsesSelectedDefinition() {
        #expect(staff.box.sorted(using: \.bySalaryDescending).map(\.name) == ["carol", "alice", "bob"])
        #expect(staff.box.sorted(using: \.byDepartmentThenName).map(\.name) == ["bob", "carol", "alice"])
    }

    @Test("the protocol's own comparableDefinition can be selected too")
    func sortedUsesProtocolRequirement() {
        #expect(staff.box.sorted(using: \.comparableDefinition).map(\.name) == ["alice", "bob", "carol"])
        #expect(staff.sorted().map(\.name) == ["alice", "bob", "carol"])
    }

    @Test("min(using:) and max(using:) follow the selected definition")
    func minAndMaxUseSelectedDefinition() {
        #expect(staff.box.min(using: \.bySalaryDescending)?.name == "carol")
        #expect(staff.box.max(using: \.bySalaryDescending)?.name == "bob")
        #expect(staff.box.min(using: \.byDepartmentThenName)?.name == "bob")
        #expect(staff.box.max(using: \.byDepartmentThenName)?.name == "alice")
    }

    @Test("min(using:) and max(using:) on an empty sequence are nil")
    func minAndMaxOnEmptySequence() {
        let empty: [Employee] = []
        #expect(empty.box.min(using: \.bySalaryDescending) == nil)
        #expect(empty.box.max(using: \.bySalaryDescending) == nil)
    }

    @Test("isSorted(using:) answers for the selected definition only")
    func isSortedUsesSelectedDefinition() {
        let bySalary = staff.box.sorted(using: \.bySalaryDescending)
        #expect(bySalary.box.isSorted(using: \.bySalaryDescending))
        #expect(!bySalary.box.isSorted(using: \.byDepartmentThenName))
    }

    @Test("isSorted(using:) is true for empty and single-element sequences")
    func isSortedOnShortSequences() {
        #expect([Employee]().box.isSorted(using: \.bySalaryDescending))
        #expect([staff[0]].box.isSorted(using: \.bySalaryDescending))
    }

    @Test("equal elements do not make isSorted(using:) false")
    func isSortedAcceptsEqualNeighbours() {
        let duplicate = Employee(name: "dave", department: "sales", salary: 10)
        #expect([duplicate, duplicate].box.isSorted(using: \.bySalaryDescending))
    }

    @Test("compare(to:using:) reports the order under the selected definition")
    func compareTwoValues() {
        // carol earns more, so she sorts first under a descending-salary definition…
        #expect(carol.box.compare(to: alice, using: \.bySalaryDescending) == .ascending)
        // …and last under one keyed on department then name.
        #expect(carol.box.compare(to: alice, using: \.byDepartmentThenName) == .ascending)
        #expect(alice.box.compare(to: carol, using: \.bySalaryDescending) == .descending)
        #expect(carol.box.compare(to: carol, using: \.bySalaryDescending) == .equal)
    }

    @Test("isLess(than:using:) agrees with compare(to:using:)")
    func isLessThanTwoValues() {
        #expect(carol.box.isLess(than: alice, using: \.bySalaryDescending))
        #expect(!alice.box.isLess(than: carol, using: \.bySalaryDescending))
        #expect(!carol.box.isLess(than: carol, using: \.bySalaryDescending))
    }

    @Test("a type that does not conform to ComparableBuildable can still carry a definition")
    func definitionOnNonConformingType() {
        let readings = [
            SensorReading(timestamp: 2, celsius: 20, note: "c"),
            SensorReading(timestamp: 1, celsius: 30, note: "b"),
            SensorReading(timestamp: 1, celsius: 40, note: "a"),
        ]
        let sorted = readings.box.sorted(using: \.byTimestampThenCelsiusDescending)
        #expect(sorted.map(\.timestamp) == [1, 1, 2])
        #expect(sorted.map(\.celsius) == [40, 30, 20])
    }

    @Test("a nil optional step sorts ahead of a non-nil one")
    func bareOptionalKeyPathStepOrdersNilFirst() {
        let readings = [
            SensorReading(timestamp: 1, celsius: 10, note: "a"),
            SensorReading(timestamp: 1, celsius: 10, note: nil),
        ]
        let sorted = readings.box.sorted(using: \.byTimestampThenCelsiusDescending)
        #expect(sorted.map(\.note) == [nil, "a"])
    }
}

// MARK: - In-place sorting

@Suite("In-place sorting through the box")
struct InPlaceSortTests {

    /// Depends on `FrameworkToolboxCompatible.box` having a setter that writes
    /// back; the `clamp` side of that same fix is pinned in
    /// `ComparableExtensionTests`.
    @Test("sort(using:) writes back")
    func sortUsingWritesBack() {
        var mutableStaff = staff
        mutableStaff.box.sort(using: \.bySalaryDescending)
        #expect(mutableStaff.map(\.name) == ["carol", "alice", "bob"])
    }

    @Test("sort(by:) writes back")
    func sortByPropertyWritesBack() {
        var mutableStaff = staff
        mutableStaff.box.sort(by: \.name)
        #expect(mutableStaff.map(\.name) == ["alice", "bob", "carol"])
    }

    @Test("sort(by:_:) descending writes back")
    func sortByPropertyDescendingWritesBack() {
        var mutableStaff = staff
        mutableStaff.box.sort(by: \.name, .descending)
        #expect(mutableStaff.map(\.name) == ["carol", "bob", "alice"])
    }
}

// MARK: - Sorting by a property key path

@Suite("Sorting by a property key path")
struct PropertyKeyPathSortTests {

    @Test("sorted(by:) defaults to ascending")
    func sortedByPropertyAscending() {
        #expect(staff.box.sorted(by: \.salary).map(\.name) == ["alice", "bob", "carol"])
    }

    @Test("sorted(by:_:) descending reverses the order")
    func sortedByPropertyDescending() {
        #expect(staff.box.sorted(by: \.name, .descending).map(\.name) == ["carol", "bob", "alice"])
    }

    @Test("descending keeps equal elements in their original relative order")
    func descendingIsStable() {
        let tickets = [
            Ticket(priority: 1, identifier: 10),
            Ticket(priority: 2, identifier: 20),
            Ticket(priority: 1, identifier: 30),
        ]
        // Reversing the sorted array instead of the comparison would give [20, 30, 10].
        #expect(tickets.box.sorted(by: \.priority, .descending).map(\.identifier) == [20, 10, 30])
    }

    @Test("works on a type with no ComparableBuildable conformance")
    func propertySortOnPlainType() {
        let tickets = [Ticket(priority: 3, identifier: 1), Ticket(priority: 1, identifier: 2)]
        #expect(tickets.box.sorted(by: \.priority).map(\.identifier) == [2, 1])
    }
}
