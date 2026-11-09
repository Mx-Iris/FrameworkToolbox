#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import Testing
@testable import ObjCRuntimeToolbox

// Initialisers, class methods and block parameters in `@RuntimeClassProxy`, and
// `@RuntimeObjectProxy`, called on real classes.

// MARK: - Initialisers

@objc(RuntimeProxyConstructible)
final class RuntimeProxyConstructible: NSObject {
    nonisolated(unsafe) static var liveInstanceCount = 0

    @objc let name: NSString
    @objc let count: Int
    @objc let scale: Float
    @objc let isEnabled: Bool

    @objc init(name: NSString, count: Int, scale: Float, enabled: Bool) {
        self.name = name
        self.count = count
        self.scale = scale
        self.isEnabled = enabled
        super.init()
        Self.liveInstanceCount += 1
    }

    @objc init?(failingWith marker: NSString) {
        return nil
    }

    deinit {
        Self.liveInstanceCount -= 1
    }
}

@RuntimeClassProxy("RuntimeProxyConstructible")
protocol RuntimeProxyConstructibleSurface {
    init?(name: NSString, count: Int, scale: Float, enabled: Bool)
    init?(failingWith marker: NSString)
    var name: NSString? { get }
    var count: Int? { get }
}

/// Serialized because the tests count the live instances of one shared class.
@Suite("@RuntimeClassProxy initialisers", .serialized)
struct RuntimeClassProxyInitialiserTests {

    @Test func initialisersAreCheckedWithTheOtherRequirements() {
        #expect(RuntimeProxyConstructibleSurfaceImplementation.isSupported)
        let selectorNames = RuntimeProxyConstructibleSurfaceImplementation.methodRequirements
            .map { NSStringFromSelector($0.selector) }
        #expect(selectorNames.contains("initWithName:count:scale:enabled:"))
        #expect(selectorNames.contains("initWithFailingWith:"))
    }

    @Test func constructsAnInstanceWithEveryArgumentInPlace() throws {
        let proxy = try #require(RuntimeProxyConstructibleSurfaceImplementation(name: "grid", count: 3, scale: 1.5, enabled: true))
        let constructed = try #require(proxy.host as? RuntimeProxyConstructible)

        #expect(proxy.name == "grid")
        #expect(proxy.count == 3)
        #expect(constructed.scale == 1.5)
        #expect(constructed.isEnabled)
    }

    @Test func constructedInstancesAreNeitherLeakedNorOverReleased() {
        let baselineCount = RuntimeProxyConstructible.liveInstanceCount

        for index in 0 ..< 1000 {
            autoreleasepool {
                let proxy = RuntimeProxyConstructibleSurfaceImplementation(name: "grid", count: index, scale: 1, enabled: false)
                #expect(proxy?.count == index)
                #expect(RuntimeProxyConstructible.liveInstanceCount == baselineCount + 1)
            }
        }

        #expect(RuntimeProxyConstructible.liveInstanceCount == baselineCount)
    }

    @Test func initialiserReturningNilYieldsNoProxy() {
        let baselineCount = RuntimeProxyConstructible.liveInstanceCount

        autoreleasepool {
            #expect(RuntimeProxyConstructibleSurfaceImplementation(failingWith: "marker") == nil)
        }

        #expect(RuntimeProxyConstructible.liveInstanceCount == baselineCount)
    }
}

// MARK: Ownership, counted exactly

/// Classes whose `+alloc` hands out an instance the test holds, and whose `init` keeps Objective-C's
/// conventions in each way an initialiser may. A class of its own per outcome: the proxy names its
/// class in a literal, and an initialiser can be added to a class once.
private enum InitialiserOutcomeFixtures {
    static let returnsReceiver: NSObject = makeHost(named: "RuntimeProxyInitialiserReturnsReceiver", outcome: .returnsReceiver)
    static let returnsNil: NSObject = makeHost(named: "RuntimeProxyInitialiserReturnsNil", outcome: .returnsNil)
    static let replacement = ReplacementFixture(named: "RuntimeProxyInitialiserReturnsReplacement")
    static let foreignObject = NSObject()
    static let returnsForeignObject: NSObject = makeHost(
        named: "RuntimeProxyInitialiserReturnsForeignObject",
        outcome: .returnsReplacement(foreignObject)
    )

    struct ReplacementFixture {
        let allocated: NSObject
        let replacement: NSObject

        init(named name: String) {
            let conventionalClass = ConventionalClass(name: name)
            let replacement = conventionalClass.makeInstance()
            allocated = conventionalClass.makeInstance()
            self.replacement = replacement
            conventionalClass.allocating(allocated)
            conventionalClass.addInitializer("init", outcome: .returnsReplacement(replacement))
        }
    }

    private static func makeHost(named name: String, outcome: ConventionalClass.InitializerOutcome) -> NSObject {
        let conventionalClass = ConventionalClass(name: name)
        let allocated = conventionalClass.makeInstance()
        conventionalClass.allocating(allocated)
        conventionalClass.addInitializer("init", outcome: outcome)
        return allocated
    }
}

@RuntimeClassProxy("RuntimeProxyInitialiserReturnsReceiver")
protocol RuntimeProxyInitialiserReturnsReceiver {
    init?()
}

@RuntimeClassProxy("RuntimeProxyInitialiserReturnsNil")
protocol RuntimeProxyInitialiserReturnsNil {
    init?()
}

@RuntimeClassProxy("RuntimeProxyInitialiserReturnsReplacement")
protocol RuntimeProxyInitialiserReturnsReplacement {
    init?()
}

@RuntimeClassProxy("RuntimeProxyInitialiserReturnsForeignObject")
protocol RuntimeProxyInitialiserReturnsForeignObject {
    init?()
}

@Suite("@RuntimeClassProxy initialiser ownership")
struct RuntimeClassProxyInitialiserOwnershipTests {

    @Test func initialiserReturningItsReceiverHandsTheProxyThatReference() {
        let allocated = InitialiserOutcomeFixtures.returnsReceiver

        let changes = retainCountChanges(of: [allocated]) {
            let proxy = RuntimeProxyInitialiserReturnsReceiverImplementation()
            #expect(proxy?.host === allocated)
        }

        #expect(changes == [0])
    }

    @Test func initialiserReturningNilKeepsTheReceiverBalanced() {
        let allocated = InitialiserOutcomeFixtures.returnsNil

        let changes = retainCountChanges(of: [allocated]) {
            #expect(RuntimeProxyInitialiserReturnsNilImplementation() == nil)
        }

        #expect(changes == [0])
    }

    @Test func initialiserReturningAnotherInstanceHandsTheProxyThatOne() {
        let fixture = InitialiserOutcomeFixtures.replacement

        let changes = retainCountChanges(of: [fixture.allocated, fixture.replacement]) {
            let proxy = RuntimeProxyInitialiserReturnsReplacementImplementation()
            #expect(proxy?.host === fixture.replacement)
        }

        #expect(changes == [0, 0])
    }

    @Test func initialiserReturningAnObjectOfAnotherClassYieldsNoProxy() {
        let allocated = InitialiserOutcomeFixtures.returnsForeignObject
        let foreignObject = InitialiserOutcomeFixtures.foreignObject

        let changes = retainCountChanges(of: [allocated, foreignObject]) {
            #expect(RuntimeProxyInitialiserReturnsForeignObjectImplementation() == nil)
        }

        #expect(changes == [0, 0])
    }
}

// MARK: Class clusters

@RuntimeClassProxy("NSDate")
protocol RuntimeProxyDateSurface {
    init?(timeIntervalSinceReferenceDate: Double)
    var timeIntervalSinceReferenceDate: Double? { get }
}

/// A public class whose `+alloc` hands out an instance of a subclass, as a class cluster's does,
/// with the subclass's `init` registered under `concreteInitialiserTypes`.
private struct ClusterFixture {
    let concreteInstance: NSObject

    init(publicName: String, concreteName: String, concreteInitialiserTypes: String) {
        let publicClass = ConventionalClass(name: publicName)
        publicClass.addInitializer("init", outcome: .returnsReceiver)
        guard let concreteClass = objc_allocateClassPair(publicClass.runtimeClass, concreteName, 0) else {
            preconditionFailure("could not allocate class \(concreteName)")
        }
        objc_registerClassPair(concreteClass)
        let returnsReceiver: @convention(block) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? = { receiver in receiver }
        class_addMethod(
            concreteClass,
            NSSelectorFromString("init"),
            imp_implementationWithBlock(returnsReceiver as AnyObject),
            concreteInitialiserTypes
        )
        concreteInstance = (concreteClass as! NSObject.Type).init()
        publicClass.allocating(concreteInstance)
    }

    static let matching = ClusterFixture(
        publicName: "RuntimeProxyClusterPublic",
        concreteName: "RuntimeProxyClusterConcrete",
        concreteInitialiserTypes: "@16@0:8"
    )
    static let mismatching = ClusterFixture(
        publicName: "RuntimeProxyMismatchedClusterPublic",
        concreteName: "RuntimeProxyMismatchedClusterConcrete",
        concreteInitialiserTypes: "@24@0:8@16"
    )
}

@RuntimeClassProxy("RuntimeProxyClusterPublic")
protocol RuntimeProxyClusterPublic {
    init?()
}

@RuntimeClassProxy("RuntimeProxyMismatchedClusterPublic")
protocol RuntimeProxyMismatchedClusterPublic {
    init?()
}

@Suite("@RuntimeClassProxy class clusters")
struct RuntimeClassProxyClusterTests {

    @Test func constructsThroughFoundationsDateCluster() throws {
        // `+[NSDate alloc]` hands out a placeholder of another class, which is where the working
        // initialiser lives.
        let proxy = try #require(RuntimeProxyDateSurfaceImplementation(timeIntervalSinceReferenceDate: 42))

        #expect(proxy.timeIntervalSinceReferenceDate == 42)
        #expect(proxy.host is NSDate)
    }

    @Test func initialiserIsLookedUpOnTheClassAllocReturned() {
        let concreteInstance = ClusterFixture.matching.concreteInstance

        let changes = retainCountChanges(of: [concreteInstance]) {
            let proxy = RuntimeProxyClusterPublicImplementation()
            #expect(proxy?.host === concreteInstance)
        }

        #expect(changes == [0])
    }

    @Test func initialiserWithAnotherSignatureOnTheAllocatedClassYieldsNoProxy() {
        let concreteInstance = ClusterFixture.mismatching.concreteInstance

        let changes = retainCountChanges(of: [concreteInstance]) {
            #expect(RuntimeProxyMismatchedClusterPublicImplementation() == nil)
        }

        #expect(changes == [0])
    }
}

// MARK: - Class Methods

@objc(RuntimeProxyFactory)
final class RuntimeProxyFactory: NSObject {
    nonisolated(unsafe) static var liveInstanceCount = 0
    nonisolated(unsafe) static let shared = RuntimeProxyFactory(serial: 0)

    @objc let serial: Int

    init(serial: Int) {
        self.serial = serial
        super.init()
        Self.liveInstanceCount += 1
    }

    deinit {
        Self.liveInstanceCount -= 1
    }

    @objc class func factory(withSerial serial: Int) -> RuntimeProxyFactory {
        RuntimeProxyFactory(serial: serial)
    }

    /// In the new family: Objective-C callers own what it returns.
    @objc class func newFactory() -> RuntimeProxyFactory {
        RuntimeProxyFactory(serial: 99)
    }

    @objc class var sharedFactory: RuntimeProxyFactory {
        shared
    }
}

@RuntimeClassProxy("RuntimeProxyFactory")
protocol RuntimeProxyFactorySurface {
    static func factoryWithSerial(_ serial: Int) -> RuntimeProxyFactory?
    static func newFactory() -> RuntimeProxyFactory?
    static var sharedFactory: RuntimeProxyFactory? { get }
    var serial: Int? { get }
}

@RuntimeClassProxy("ThisClassIsNotPresentInThisProcess")
protocol RuntimeProxyAbsentFactorySurface {
    static func make() -> NSObject?
}

/// Serialized because the tests count the live instances of one shared class.
@Suite("@RuntimeClassProxy class methods", .serialized)
struct RuntimeClassProxyClassMethodTests {

    @Test func classMethodsAreCheckedAsClassMethods() {
        #expect(RuntimeProxyFactorySurfaceImplementation.isSupported)
        let classMethodNames = RuntimeProxyFactorySurfaceImplementation.methodRequirements
            .filter { !$0.isInstanceMethod }
            .map { NSStringFromSelector($0.selector) }
        #expect(Set(classMethodNames) == ["factoryWithSerial:", "newFactory", "sharedFactory"])
    }

    @Test func classMethodsAreSentToTheClass() {
        #expect(RuntimeProxyFactorySurfaceImplementation.factoryWithSerial(7)?.serial == 7)
        #expect(RuntimeProxyFactorySurfaceImplementation.sharedFactory === RuntimeProxyFactory.shared)
    }

    @Test func classMethodResultsFollowTheMethodFamilies() {
        _ = RuntimeProxyFactory.shared
        let baselineCount = RuntimeProxyFactory.liveInstanceCount

        // A +1 `newFactory` read as +0 would leak one instance per call, and a +0
        // `factoryWithSerial:` read as +1 would release one too many.
        for _ in 0 ..< 1000 {
            autoreleasepool {
                #expect(RuntimeProxyFactorySurfaceImplementation.newFactory()?.serial == 99)
                #expect(RuntimeProxyFactorySurfaceImplementation.factoryWithSerial(1)?.serial == 1)
                #expect(RuntimeProxyFactorySurfaceImplementation.sharedFactory != nil)
            }
        }

        #expect(RuntimeProxyFactory.liveInstanceCount == baselineCount)
    }

    @Test func classMethodOfAnAbsentClassReturnsNil() {
        #expect(RuntimeProxyAbsentFactorySurfaceImplementation.isSupported == false)
        #expect(RuntimeProxyAbsentFactorySurfaceImplementation.make() == nil)
    }
}

// MARK: - Block Parameters

@objc(RuntimeProxyBlockHost)
final class RuntimeProxyBlockHost: NSObject {
    @objc dynamic var storedHandler: ((Bool) -> Void)?

    @objc dynamic func perform(withHandler handler: @escaping (Bool) -> Void) {
        storedHandler = handler
    }

    @objc dynamic func performIfPossible(_ handler: ((Int) -> Void)?) {
        handler?(42)
    }

    @objc dynamic class func announce(_ handler: @escaping (NSString) -> Void) {
        handler("announced")
    }
}

@RuntimeClassProxy("RuntimeProxyBlockHost")
protocol RuntimeProxyBlockHostSurface {
    func performWithHandler(_ handler: @escaping @convention(block) (Bool) -> Void)
    func performIfPossible(_ handler: (@convention(block) (Int) -> Void)?)
    static func announce(_ handler: @escaping @convention(block) (NSString) -> Void)
}

@Suite("@RuntimeClassProxy block parameters")
struct RuntimeClassProxyBlockTests {

    @Test func blockParametersMatchTheLiveMethods() {
        #expect(RuntimeProxyBlockHostSurfaceImplementation.isSupported)
    }

    @Test func blockIsHandedOverForTheCalleeToKeep() throws {
        let host = RuntimeProxyBlockHost()
        let proxy = try #require(RuntimeProxyBlockHostSurfaceImplementation(host))
        var receivedValue: Bool?

        proxy.performWithHandler { value in receivedValue = value }
        host.storedHandler?(true)

        #expect(receivedValue == true)
    }

    @Test func optionalBlockIsPassedOrLeftOut() throws {
        let proxy = try #require(RuntimeProxyBlockHostSurfaceImplementation(RuntimeProxyBlockHost()))
        var receivedValue: Int?

        proxy.performIfPossible { value in receivedValue = value }
        proxy.performIfPossible(nil)

        #expect(receivedValue == 42)
    }

    @Test func blockReachesAClassMethod() {
        var announcement: NSString?

        RuntimeProxyBlockHostSurfaceImplementation.announce { announcement = $0 }

        #expect(announcement == "announced")
    }
}

// MARK: - @RuntimeObjectProxy

@objc(RuntimeObjectProxyFirstHost)
final class RuntimeObjectProxyFirstHost: NSObject {
    @objc dynamic var level: Int = 1
    @objc dynamic func identifier() -> NSString { "first" }
    @objc dynamic func deliver(_ handler: @escaping (NSString) -> Void) { handler("first") }
}

/// Unrelated to the first host, with the same methods.
@objc(RuntimeObjectProxySecondHost)
final class RuntimeObjectProxySecondHost: NSObject {
    @objc dynamic var level: Int = 2
    @objc dynamic func identifier() -> NSString { "second" }
    @objc dynamic func deliver(_ handler: @escaping (NSString) -> Void) { handler("second") }
}

/// The same selectors, with `identifier` returning a scalar.
@objc(RuntimeObjectProxyMismatchedHost)
final class RuntimeObjectProxyMismatchedHost: NSObject {
    @objc dynamic var level: Int = 3
    @objc dynamic func identifier() -> Int { 3 }
    @objc dynamic func deliver(_ handler: @escaping (NSString) -> Void) { handler("mismatched") }
}

@RuntimeObjectProxy
protocol RuntimeObjectProxyIdentified {
    var level: Int? { get }
    func identifier() -> NSString?
    func deliver(_ handler: @escaping @convention(block) (NSString) -> Void)
}

@Suite("@RuntimeObjectProxy")
struct RuntimeObjectProxyTests {

    @Test func listsWhatItChecks() {
        let selectorNames = RuntimeObjectProxyIdentifiedImplementation.methodRequirements
            .map { NSStringFromSelector($0.selector) }
        #expect(selectorNames == ["level", "identifier", "deliver:"])
    }

    @Test func wrapsObjectsOfUnrelatedClassesThatShareTheMethods() throws {
        let first = try #require(RuntimeObjectProxyIdentifiedImplementation(RuntimeObjectProxyFirstHost()))
        let second = try #require(RuntimeObjectProxyIdentifiedImplementation(RuntimeObjectProxySecondHost()))
        var delivered: [NSString] = []

        first.deliver { delivered.append($0) }
        second.deliver { delivered.append($0) }

        #expect(first.identifier() == "first")
        #expect(first.level == 1)
        #expect(second.identifier() == "second")
        #expect(second.level == 2)
        #expect(delivered == ["first", "second"])
    }

    @Test func refusesAnObjectWhoseClassChangedASignature() {
        #expect(RuntimeObjectProxyIdentifiedImplementation(RuntimeObjectProxyMismatchedHost()) == nil)
        // Asked again, the answer comes from the record kept for the class.
        #expect(RuntimeObjectProxyIdentifiedImplementation(RuntimeObjectProxyMismatchedHost()) == nil)
    }

    @Test func refusesAnObjectMissingAMethod() {
        #expect(RuntimeObjectProxyIdentifiedImplementation(NSObject()) == nil)
    }
}

// MARK: - @RuntimeClassHook

@objc(RuntimeHookBlockHost)
final class RuntimeHookBlockHost: NSObject {
    @objc dynamic func deliver(_ handler: @escaping (NSString) -> Void) {
        handler("original")
    }
}

@RuntimeClassHook("RuntimeHookBlockHost")
struct RuntimeHookBlockHostHooks {
    @RuntimeMethodReplacement
    func deliver(_ handler: @escaping @convention(block) (NSString) -> Void) {
        callOriginal { value in handler("hooked \(value)" as NSString) }
    }
}

@Suite("@RuntimeClassHook block parameters")
struct RuntimeClassHookBlockTests {

    @Test func replacementReceivesAndForwardsABlock() throws {
        try RuntimeHookBlockHostHooks.install()
        var delivered: NSString?

        RuntimeHookBlockHost().deliver { delivered = $0 }

        #expect(delivered == "hooked original")
    }
}
#endif
