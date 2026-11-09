#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import Testing
@testable import ObjCRuntimeToolbox

// MARK: - @RuntimeClassProxy

/// The host the proxy below calls into: one method in the new family — a leading underscore does
/// not take it out — and one whose name only starts like the copy family.
private enum MethodFamilyProxyFixture {
    static let retainedResult = NSObject()
    static let unretainedResult = NSObject()
    static let host: NSObject = {
        let conventionalClass = ConventionalClass(name: "MethodFamilyProxyHost")
        conventionalClass.addMethod("_newItem", returning: retainedResult, isRetained: true)
        conventionalClass.addMethod("copyright", returning: unretainedResult, isRetained: false)
        return conventionalClass.makeInstance()
    }()
}

@RuntimeClassProxy("MethodFamilyProxyHost")
protocol MethodFamilyProxyHost {
    func _newItem() -> NSObject?
    func copyright() -> NSObject?
}

/// Serialized because both tests count references on the one shared host — the proxy needs its
/// class name as a literal, so there is only one — and running side by side, each would count the
/// other's references too.
@Suite("@RuntimeClassProxy method families", .serialized)
struct RuntimeClassProxyMethodFamilyTests {

    @Test func proxyTakesOverTheReferenceAMethodInARetainingFamilyHandsIt() throws {
        let host = MethodFamilyProxyFixture.host
        let result = MethodFamilyProxyFixture.retainedResult

        let changes = retainCountChanges(of: [host, result]) {
            let proxy = MethodFamilyProxyHostImplementation(host)
            #expect(proxy?._newItem() === result)
        }

        #expect(changes == [0, 0])
    }

    @Test func proxyLeavesAloneTheResultOfAMethodOutsideTheFamilies() throws {
        let host = MethodFamilyProxyFixture.host
        let result = MethodFamilyProxyFixture.unretainedResult

        let changes = retainCountChanges(of: [host, result]) {
            let proxy = MethodFamilyProxyHostImplementation(host)
            #expect(proxy?.copyright() === result)
        }

        #expect(changes == [0, 0])
    }
}

// MARK: - @RuntimeClassHook

/// A replacement that returns nothing cannot get ownership wrong, so a method whose name puts it in a
/// family stays replaceable when it returns `Void` — the standard `copy:` action is one.
@objc(MethodFamilyHookHost)
final class MethodFamilyHookHost: NSObject {
    @objc dynamic var copiedSources: [String] = []

    @objc dynamic func copyFrom(_ source: NSString) {
        copiedSources.append(source as String)
    }
}

@RuntimeClassHook("MethodFamilyHookHost")
struct MethodFamilyHookHostHooks {
    @RuntimeMethodReplacement
    func copyFrom(_ source: NSString) {
        callOriginal(source.uppercased as NSString)
    }
}

@Suite("@RuntimeClassHook method families")
struct RuntimeClassHookMethodFamilyTests {

    @Test func voidMethodInACopyFamilyIsReplaced() throws {
        try MethodFamilyHookHostHooks.install()
        let host = MethodFamilyHookHost()

        host.copyFrom("source")

        #expect(host.copiedSources == ["SOURCE"])
    }
}
#endif
