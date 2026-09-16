import Foundation
import Testing

// Deliberately not `@testable`: every type under test here is public API, and a plain
// import is what proves it.
import FoundationToolbox

// MARK: - Bridging

/// Casts through `Any`, which is the same runtime path a call site's `as?` takes but
/// without the compiler's misleading `conditional cast ... always succeeds` diagnostic on
/// the literal spelling. That diagnostic, and why the API recommends
/// `init(validating:)` instead, is documented on `ObjectiveCCollectionHandle`.
private func bridging<Handle>(_ collection: Any, to handleType: Handle.Type) -> Handle? {
    collection as? Handle
}


@Suite("Typed collection handles bridge as their wrapped collection")
struct ObjectiveCCollectionBridgingTests {

    // The whole point of conforming to `_ObjectiveCBridgeable`. Without it a handle
    // reaching an `Any` or `AnyObject` parameter would be boxed in a `_SwiftValue`, and
    // Objective-C would see an opaque object instead of an array.
    @Test func handleReachingAnAnyObjectParameterArrivesAsAnNSArray() {
        let names = NSArrayOf<String>(["Ada", "Grace"])
        let bridged = names as AnyObject
        #expect(bridged is NSArray)
        #expect((bridged as? NSArray)?.count == 2)
    }

    @Test func bridgingHandsBackTheVeryObjectTheHandleWraps() {
        let storage = NSMutableArray()
        let names = NSMutableArrayOf<String>(rawValue: storage)
        #expect((names as AnyObject) === storage)
    }

    @Test func handleStoredIntoAnObjectiveCContainerIsReadBackAsACollection() {
        let userInfo = NSMutableDictionary()
        userInfo.setObject(NSArrayOf<String>(["Ada"]), forKey: "names" as NSString)
        #expect(userInfo.object(forKey: "names") is NSArray)
    }

    @Test func conditionalBridgingAcceptsACollectionWhoseElementsAllMatch() throws {
        let storage: NSArray = ["Ada", "Grace"]
        let names = try #require(bridging(storage, to: NSArrayOf<String>.self))
        #expect(Array(names) == ["Ada", "Grace"])
    }

    @Test func conditionalBridgingRejectsACollectionHoldingAnUnexpectedElement() {
        let storage: NSArray = ["Ada", 42]
        #expect(bridging(storage, to: NSArrayOf<String>.self) == nil)
    }

    @Test func conditionalBridgingOfAnAnyElementSkipsValidationEntirely() {
        let storage: NSArray = ["Ada", 42]
        #expect(bridging(storage, to: NSArrayOf<Any>.self) != nil)
    }

    @Test func conditionalBridgingChecksBothKeysAndValuesOfADictionary() {
        let storage: NSDictionary = ["tempo": 120]
        #expect(bridging(storage, to: NSDictionaryOf<String, Int>.self) != nil)
        #expect(bridging(storage, to: NSDictionaryOf<String, String>.self) == nil)
        #expect(bridging(storage, to: NSDictionaryOf<Int, Int>.self) == nil)
    }

    @Test func conditionalBridgingValidatesSetElements() {
        let storage: NSSet = ["Ada", "Grace"]
        #expect(bridging(storage, to: NSSetOf<String>.self) != nil)
        #expect(bridging(storage, to: NSSetOf<Int>.self) == nil)
    }

    // The spelling the API recommends, for the reason documented on the initializer:
    // writing `as?` against a source already typed as the `_ObjectiveCType` earns a
    // `conditional cast ... always succeeds` warning at every call site.

    @Test func validatingInitializerAcceptsAMatchingCollection() throws {
        let storage: NSArray = ["Ada", "Grace"]
        let names = try #require(NSArrayOf<String>(validating: storage))
        #expect(Array(names) == ["Ada", "Grace"])
    }

    @Test func validatingInitializerRejectsAnUnexpectedElement() {
        let storage: NSArray = ["Ada", 42]
        #expect(NSArrayOf<String>(validating: storage) == nil)
    }

    @Test func validatingInitializerWrapsWithoutCopying() throws {
        let storage = NSMutableArray(array: ["Ada"])
        let names = try #require(NSMutableArrayOf<String>(validating: storage))
        names.append("Grace")
        #expect(storage.count == 2)
    }

    // The protocol admits a `nil` source: an Objective-C method declared `nonnull` that
    // returned `nil` anyway. Every handle answers with an empty collection.
    @Test func bridgingFromANilSourceYieldsAnEmptyCollection() {
        #expect(NSArrayOf<String>._unconditionallyBridgeFromObjectiveC(nil).isEmpty)
        #expect(NSSetOf<String>._unconditionallyBridgeFromObjectiveC(nil).count == 0)
        #expect(NSDictionaryOf<String, Int>._unconditionallyBridgeFromObjectiveC(nil).isEmpty)
    }
}

// MARK: - Reference semantics

@Suite("Handles share the collection rather than copying it")
struct ObjectiveCCollectionReferenceSemanticsTests {

    @Test func copyingAHandleSharesTheUnderlyingCollection() {
        let original = NSMutableArrayOf<String>()
        let alias = original
        alias.append("Ada")
        #expect(original.count == 1)
        #expect(original[0] == "Ada")
    }

    @Test func aHandleBoundWithLetCanStillBeMutated() {
        let names = NSMutableArrayOf<String>()
        names.append("Ada")
        names.append("Grace")
        #expect(Array(names) == ["Ada", "Grace"])
    }

    @Test func sharingInitializerDoesNotCopy() {
        let mutableNames = NSMutableArrayOf<String>(["Ada"])
        let sharedNames = NSArrayOf(sharing: mutableNames)
        mutableNames.append("Grace")
        #expect(sharedNames.count == 2)
    }

    @Test func copyProducesASnapshotThatStopsTracking() {
        let names = NSMutableArrayOf<String>(["Ada"])
        let snapshot = names.copy()
        names.append("Grace")
        #expect(snapshot.count == 1)
        #expect(names.count == 2)
    }

    @Test func mutableCopyProducesAnIndependentMutableCollection() {
        let names = NSArrayOf<String>(["Ada"])
        let editableNames = names.mutableCopy()
        editableNames.append("Grace")
        #expect(names.count == 1)
        #expect(editableNames.count == 2)
    }

    // Reference semantics is not an abstract preference — this is the case a Swift
    // `[String]` cannot serve. The key-value-coding proxy has to be the object that gets
    // mutated, or the change never reaches the host object.
    @Test func mutatingThroughAHandleOverAKeyValueCodingProxyWritesBackToTheHost() {
        let playlist = Playlist()
        let tracks = NSMutableArrayOf<String>(rawValue: playlist.mutableArrayValue(forKey: "tracks"))
        tracks.append("Blue in Green")
        #expect(playlist.tracks.count == 1)
        #expect(playlist.tracks.object(at: 0) as? String == "Blue in Green")
    }
}

/// A key-value-coding host for `mutatingThroughAHandleOverAKeyValueCodingProxyWritesBackToTheHost`.
private final class Playlist: NSObject {
    @objc dynamic var tracks: NSArray = NSArray()
}

// MARK: - Arrays

@Suite("NSArrayOf and NSMutableArrayOf")
struct TypedArrayHandleTests {

    @Test func elementsBridgeBetweenSwiftAndObjectiveCRepresentations() {
        let names = NSMutableArrayOf<String>()
        names.append("Ada")
        #expect(names.rawValue.object(at: 0) is NSString)
        #expect(names[0] == "Ada")
    }

    @Test func arrayLiteralBuildsAHandle() {
        let names: NSArrayOf<String> = ["Ada", "Grace"]
        #expect(Array(names) == ["Ada", "Grace"])
    }

    @Test func handleIteratesInOrder() {
        let numbers = NSArrayOf<Int>([3, 1, 2])
        #expect(Array(numbers) == [3, 1, 2])
    }

    @Test func randomAccessCollectionConformanceSuppliesTheUsualOperations() {
        let numbers = NSArrayOf<Int>([3, 1, 2])
        #expect(numbers.count == 3)
        #expect(numbers.first == 3)
        #expect(numbers.last == 2)
        #expect(numbers.sorted() == [1, 2, 3])
        #expect(numbers.isEmpty == false)
        #expect(NSArrayOf<Int>().isEmpty)
    }

    @Test func subscriptSetterReplacesInPlace() {
        let names = NSMutableArrayOf<String>(["Ada", "Grace"])
        names[1] = "Katherine"
        #expect(Array(names) == ["Ada", "Katherine"])
    }

    @Test func mutationOperationsChangeTheSharedCollection() {
        let names = NSMutableArrayOf<String>(["Ada"])
        names.append(contentsOf: ["Grace", "Katherine"])
        names.insert("Dorothy", at: 0)
        names.remove(at: 1)
        #expect(Array(names) == ["Dorothy", "Grace", "Katherine"])
        names.removeLast()
        #expect(Array(names) == ["Dorothy", "Grace"])
        names.removeAll()
        #expect(names.isEmpty)
    }

    @Test func equalityComparesContentsNotIdentity() {
        #expect(NSArrayOf<String>(["Ada"]) == NSArrayOf<String>(["Ada"]))
        #expect(NSArrayOf<String>(["Ada"]) != NSArrayOf<String>(["Grace"]))
    }
}

// MARK: - Dictionaries

@Suite("NSDictionaryOf and NSMutableDictionaryOf")
struct TypedDictionaryHandleTests {

    @Test func dictionaryLiteralBuildsAHandle() {
        let tempos: NSDictionaryOf<String, Int> = ["Blue in Green": 120]
        #expect(tempos["Blue in Green"] == 120)
        #expect(tempos.count == 1)
    }

    @Test func lookupOfAnAbsentKeyIsNil() {
        let tempos: NSDictionaryOf<String, Int> = ["Blue in Green": 120]
        #expect(tempos["So What"] == nil)
    }

    @Test func subscriptSetterInsertsAndUpdates() {
        let tempos = NSMutableDictionaryOf<String, Int>()
        tempos["Blue in Green"] = 120
        #expect(tempos["Blue in Green"] == 120)
        tempos["Blue in Green"] = 96
        #expect(tempos["Blue in Green"] == 96)
        #expect(tempos.count == 1)
    }

    @Test func assigningNilRemovesTheKey() {
        let tempos = NSMutableDictionaryOf<String, Int>(["Blue in Green": 120])
        tempos["Blue in Green"] = nil
        #expect(tempos["Blue in Green"] == nil)
        #expect(tempos.isEmpty)
    }

    @Test func iterationYieldsEveryPair() {
        let tempos: NSDictionaryOf<String, Int> = ["Blue in Green": 120, "So What": 136]
        let collected = Dictionary(uniqueKeysWithValues: tempos.map { ($0.key, $0.value) })
        #expect(collected == ["Blue in Green": 120, "So What": 136])
    }

    @Test func swiftDictionaryConversionRoundTrips() {
        let source = ["Blue in Green": 120, "So What": 136]
        #expect(NSDictionaryOf(source).swiftDictionary == source)
    }

    @Test func keysAndValuesAreTyped() {
        let tempos: NSDictionaryOf<String, Int> = ["Blue in Green": 120]
        #expect(tempos.keys == ["Blue in Green"])
        #expect(tempos.values == [120])
    }

    @Test func mutationOperationsChangeTheSharedCollection() {
        let tempos = NSMutableDictionaryOf<String, Int>()
        tempos.setValue(120, for: "Blue in Green")
        #expect(tempos["Blue in Green"] == 120)
        tempos.removeValue(for: "Blue in Green")
        #expect(tempos.isEmpty)
    }
}

// MARK: - Sets

@Suite("NSSetOf and NSMutableSetOf")
struct TypedSetHandleTests {

    @Test func arrayLiteralBuildsAHandleAndDeduplicates() {
        let names: NSSetOf<String> = ["Ada", "Grace", "Ada"]
        #expect(names.count == 2)
    }

    @Test func membershipUsesObjectiveCEquality() {
        let names: NSSetOf<String> = ["Ada", "Grace"]
        #expect(names.contains("Ada"))
        #expect(names.contains("Katherine") == false)
    }

    @Test func iterationYieldsEveryElement() {
        let names: NSSetOf<String> = ["Ada", "Grace"]
        #expect(Set(names) == ["Ada", "Grace"])
    }

    @Test func swiftSetConversionRoundTrips() {
        let source: Set<String> = ["Ada", "Grace"]
        #expect(NSSetOf(source).swiftSet == source)
    }

    @Test func mutationOperationsChangeTheSharedCollection() {
        let names = NSMutableSetOf<String>()
        names.insert("Ada")
        names.insert(contentsOf: ["Grace", "Katherine"])
        #expect(names.count == 3)
        names.remove("Grace")
        #expect(names.contains("Grace") == false)
        names.removeAll()
        #expect(names.isEmpty)
    }
}
