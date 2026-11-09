#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import Testing
@testable import ObjCRuntimeToolbox

// MARK: - Initialisers

/// An initialiser consumes the reference to its receiver and returns a reference to its result, so
/// `[[Class alloc] init…]` hands over exactly one object whatever the initialiser decides to return.
@Suite("DynamicObject initialiser ownership")
struct DynamicObjectInitializerOwnershipTests {

    @Test func initializerReturningItsReceiverHandsItOver() {
        let conventionalClass = ConventionalClass(uniqueName: "ReturnsReceiver")
        let instance = conventionalClass.makeInstance()
        conventionalClass.allocating(instance)
        conventionalClass.addInitializer("initReturningReceiver", outcome: .returnsReceiver)

        let changes = retainCountChanges(of: [instance]) {
            let constructed = DynamicObject(className: conventionalClass.name).initReturningReceiver()
            #expect(constructed.asAnyObject === instance)
        }

        #expect(changes == [0])
    }

    @Test func initializerReturningNilReleasesItsReceiverOnce() {
        let conventionalClass = ConventionalClass(uniqueName: "ReturnsNil")
        let instance = conventionalClass.makeInstance()
        conventionalClass.allocating(instance)
        conventionalClass.addInitializer("initReturningNil", outcome: .returnsNil)

        let changes = retainCountChanges(of: [instance]) {
            let constructed = DynamicObject(className: conventionalClass.name).initReturningNil()
            #expect(constructed.asAnyObject == nil)
        }

        #expect(changes == [0])
    }

    @Test func initializerReturningAReplacementReleasesItsReceiverAndHandsOverTheReplacement() {
        let conventionalClass = ConventionalClass(uniqueName: "ReturnsReplacement")
        let instance = conventionalClass.makeInstance()
        let replacement = conventionalClass.makeInstance()
        conventionalClass.allocating(instance)
        conventionalClass.addInitializer("initReturningReplacement", outcome: .returnsReplacement(replacement))

        let changes = retainCountChanges(of: [instance, replacement]) {
            let constructed = DynamicObject(className: conventionalClass.name).initReturningReplacement()
            #expect(constructed.asAnyObject === replacement)
        }

        #expect(changes == [0, 0])
    }
}

// MARK: - Method families

/// Which methods hand over a reference is decided by the selector's family, and a selector is in a
/// family only when, leading underscores aside, the family's name is followed by something other
/// than a lowercase letter.
@Suite("DynamicObject method family ownership")
struct DynamicObjectMethodFamilyOwnershipTests {

    @Test(arguments: ["newItem", "copyItem", "mutableCopyItem", "_newItem", "__copyItem"])
    func methodInARetainingFamilyHandsOverItsResult(selectorName: String) {
        let conventionalClass = ConventionalClass(uniqueName: "Retaining\(selectorName)")
        let receiver = conventionalClass.makeInstance()
        let result = conventionalClass.makeInstance()
        conventionalClass.addMethod(selectorName, returning: result, isRetained: true)

        let changes = retainCountChanges(of: [receiver, result]) {
            let member: DynamicObject = DynamicObject(receiver)[dynamicMember: selectorName]
            #expect(member.asAnyObject === result)
        }

        #expect(changes == [0, 0])
    }

    @Test(arguments: ["newsItem", "copyright", "allocator", "initials", "mutableCopyright"])
    func methodNamedLikeAFamilyButOutsideItReturnsWithoutHandingOver(selectorName: String) {
        let conventionalClass = ConventionalClass(uniqueName: "Unretained\(selectorName)")
        let receiver = conventionalClass.makeInstance()
        let result = conventionalClass.makeInstance()
        conventionalClass.addMethod(selectorName, returning: result, isRetained: false)

        let changes = retainCountChanges(of: [receiver, result]) {
            let member: DynamicObject = DynamicObject(receiver)[dynamicMember: selectorName]
            #expect(member.asAnyObject === result)
        }

        #expect(changes == [0, 0])
    }

    /// `ObjCMethodFamily` is the whole rule, so its edges are pinned directly as well.
    @Test func familyMembershipFollowsTheNamingRule() {
        #expect(ObjCMethodFamily(selectorName: "init") == .`init`)
        #expect(ObjCMethodFamily(selectorName: "initWithFrame:connection:") == .`init`)
        #expect(ObjCMethodFamily(selectorName: "_init") == .`init`)
        #expect(ObjCMethodFamily(selectorName: "initialize") == nil)
        #expect(ObjCMethodFamily(selectorName: "alloc") == .alloc)
        #expect(ObjCMethodFamily(selectorName: "allocWithZone:") == .alloc)
        #expect(ObjCMethodFamily(selectorName: "copy:") == .copy)
        #expect(ObjCMethodFamily(selectorName: "copy2") == .copy)
        #expect(ObjCMethodFamily(selectorName: "mutableCopyWithZone:") == .mutableCopy)
        #expect(ObjCMethodFamily(selectorName: "new") == .new)
        #expect(ObjCMethodFamily(selectorName: "new_item") == .new)
        #expect(ObjCMethodFamily(selectorName: "newsItem") == nil)
        #expect(ObjCMethodFamily(selectorName: "renew") == nil)
        #expect(ObjCMethodFamily(selectorName: "_") == nil)
        #expect(ObjCMethodFamily(selectorName: "") == nil)
    }
}
#endif
