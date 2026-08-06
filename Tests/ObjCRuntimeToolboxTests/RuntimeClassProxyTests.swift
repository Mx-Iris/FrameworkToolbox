#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import XCTest
@testable import ObjCRuntimeToolbox

// MARK: - Targets

@objc(RuntimeProxyTarget)
final class RuntimeProxyTarget: NSObject {
    @objc dynamic var label: NSString? = "initial"
    @objc dynamic var counter: Int = 0

    @objc dynamic func describe() -> NSString { "described" }
    @objc dynamic func reset() { counter = 0 }
    @objc dynamic func combine(_ left: Int, with right: Int) -> Int { left + right }
    @objc dynamic func isReady() -> Bool { counter > 0 }
}

@objc(RuntimeProxyUnrelated)
final class RuntimeProxyUnrelated: NSObject {}

/// Counts its own instances so an ownership mistake shows up as a number rather
/// than as a crash somewhere later.
@objc(RuntimeProxyPayload)
final class RuntimeProxyPayload: NSObject {
    nonisolated(unsafe) static var liveInstanceCount = 0

    override init() {
        super.init()
        Self.liveInstanceCount += 1
    }

    deinit {
        Self.liveInstanceCount -= 1
    }
}

@objc(RuntimeProxyOwner)
final class RuntimeProxyOwner: NSObject {
    @objc dynamic var payload = RuntimeProxyPayload()
    @objc dynamic func currentPayload() -> RuntimeProxyPayload { payload }
}

// MARK: - Proxies

@RuntimeClassProxy("RuntimeProxyTarget")
protocol RuntimeProxyTargetSurface {
    var label: NSString? { get set }
    var counter: Int? { get }
    func describe() -> NSString?
    func reset()
    func combine(_ left: Int, with right: Int) -> Int?
    func isReady() -> Bool?
}

@RuntimeClassProxy("RuntimeProxyOwner")
protocol RuntimeProxyOwnerSurface {
    func currentPayload() -> AnyObject?
}

@RuntimeClassProxy("ThisClassIsNotPresentInThisProcess")
protocol RuntimeProxyAbsentSurface {
    func anything()
}

// MARK: - Tests

final class RuntimeClassProxyTests: XCTestCase {

    // MARK: Support detection

    func testProxyIsSupportedWhenTheClassMatches() {
        XCTAssertTrue(RuntimeProxyTargetSurfaceImplementation.isSupported)
        XCTAssertEqual(RuntimeProxyTargetSurfaceImplementation.runtimeClassName, "RuntimeProxyTarget")
    }

    func testDerivedRequirementsMatchTheLiveMethods() {
        for requirement in RuntimeProxyTargetSurfaceImplementation.methodRequirements {
            let liveEncoding = RuntimeMethodInspector.typeEncoding(
                forClassNamed: RuntimeProxyTargetSurfaceImplementation.runtimeClassName,
                selector: requirement.selector
            )
            XCTAssertNotNil(liveEncoding, "\(requirement.selector) is missing from the runtime")
            guard let liveEncoding else { continue }
            XCTAssertTrue(
                ObjCTypeEncodingNormalization.matches(requirement.typeEncoding, liveEncoding),
                "\(requirement.selector): derived \(requirement.typeEncoding), runtime reports \(liveEncoding)"
            )
        }
    }

    func testDerivedRequirementsCoverGettersAndSetters() {
        let selectorNames = RuntimeProxyTargetSurfaceImplementation.methodRequirements
            .map { NSStringFromSelector($0.selector) }

        // `var label: NSString? { get set }` has to produce both halves.
        XCTAssertTrue(selectorNames.contains("label"))
        XCTAssertTrue(selectorNames.contains("setLabel:"))
        XCTAssertTrue(selectorNames.contains("counter"))
        XCTAssertFalse(selectorNames.contains("setCounter:"), "a { get }-only property must not require a setter")
        XCTAssertTrue(selectorNames.contains("combine:with:"))
    }

    func testProxyForAnAbsentClassIsUnsupported() {
        XCTAssertFalse(RuntimeProxyAbsentSurfaceImplementation.isSupported)
        XCTAssertNil(RuntimeProxyAbsentSurfaceImplementation(NSObject()))
    }

    // MARK: Wrapping

    func testProxyWrapsAMatchingInstance() {
        XCTAssertNotNil(RuntimeProxyTargetSurfaceImplementation(RuntimeProxyTarget()))
    }

    func testProxyRefusesAnUnrelatedInstance() {
        // The signature check proves the class matches; this proves the object
        // does. Without it the proxy would marshal arguments into whatever the
        // unrelated object's method table happens to point at.
        XCTAssertNil(RuntimeProxyTargetSurfaceImplementation(RuntimeProxyUnrelated()))
        XCTAssertNil(RuntimeProxyTargetSurfaceImplementation(NSString("not a target")))
    }

    // MARK: Dispatch

    func testVoidAndIntegerDispatch() throws {
        let target = RuntimeProxyTarget()
        target.counter = 7
        let proxy = try XCTUnwrap(RuntimeProxyTargetSurfaceImplementation(target))

        XCTAssertEqual(proxy.counter, 7)

        proxy.reset()
        XCTAssertEqual(target.counter, 0)
        XCTAssertEqual(proxy.counter, 0)
    }

    func testMultipleArgumentDispatch() throws {
        let proxy = try XCTUnwrap(RuntimeProxyTargetSurfaceImplementation(RuntimeProxyTarget()))
        XCTAssertEqual(proxy.combine(11, with: 31), 42)
    }

    func testBooleanReturnDispatch() throws {
        let target = RuntimeProxyTarget()
        let proxy = try XCTUnwrap(RuntimeProxyTargetSurfaceImplementation(target))

        XCTAssertEqual(proxy.isReady(), false)
        target.counter = 1
        XCTAssertEqual(proxy.isReady(), true)
    }

    func testObjectReturnDispatch() throws {
        let proxy = try XCTUnwrap(RuntimeProxyTargetSurfaceImplementation(RuntimeProxyTarget()))
        XCTAssertEqual(proxy.describe(), "described")
    }

    func testPropertyGetterAndSetterDispatch() throws {
        let target = RuntimeProxyTarget()
        let proxy = try XCTUnwrap(RuntimeProxyTargetSurfaceImplementation(target))

        XCTAssertEqual(proxy.label, "initial")

        proxy.label = "rewritten"
        XCTAssertEqual(target.label, "rewritten", "the setter should have reached the host")
        XCTAssertEqual(proxy.label, "rewritten")

        proxy.label = nil
        XCTAssertNil(target.label)
        XCTAssertNil(proxy.label)
    }

    // MARK: Ownership

    func testRepeatedObjectReturnsDoNotOverRelease() throws {
        let baselineCount = RuntimeProxyPayload.liveInstanceCount

        try autoreleasepool {
            let owner = RuntimeProxyOwner()
            let proxy = try XCTUnwrap(RuntimeProxyOwnerSurfaceImplementation(owner))
            XCTAssertEqual(RuntimeProxyPayload.liveInstanceCount, baselineCount + 1)

            // A +0 return consumed as though it were +1 would drop the payload's
            // retain count once per call. A thousand calls makes that unmissable
            // — either the count goes wrong or the process dies.
            for _ in 0 ..< 1000 {
                autoreleasepool {
                    let returned = proxy.currentPayload()
                    XCTAssertNotNil(returned)
                    XCTAssertTrue(returned === owner.payload)
                }
            }

            XCTAssertEqual(
                RuntimeProxyPayload.liveInstanceCount,
                baselineCount + 1,
                "the payload should still be alive and unduplicated after 1000 proxied reads"
            )
            XCTAssertNotNil(owner.payload)
        }

        XCTAssertEqual(
            RuntimeProxyPayload.liveInstanceCount,
            baselineCount,
            "the payload should have been released exactly once, when its owner went away"
        )
    }
}

#endif
