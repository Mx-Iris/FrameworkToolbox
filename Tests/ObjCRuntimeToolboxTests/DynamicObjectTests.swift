#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import Testing
@testable import ObjCRuntimeToolbox

private func runtimeClassName(of object: NSObject?) -> String? {
    object.map { NSStringFromClass(type(of: $0)) }
}

// MARK: - Construction

@Suite("DynamicObject construction")
struct DynamicObjectConstructionTests {

    @Test func parameterlessInitAllocatesTheRealClass() {
        let formatter = ObjC.NSDateFormatter()

        #expect(runtimeClassName(of: formatter.asObject) == "NSDateFormatter")
        #expect(formatter.asObject is DateFormatter)
    }

    @Test func explicitInitMatchesTheImplicitOne() {
        let formatter = ObjC.NSDateFormatter.`init`()

        #expect(runtimeClassName(of: formatter.asObject) == "NSDateFormatter")
    }

    @Test func parameterizedInitPassesItsArgument() {
        let uuidString = "68753A44-4D6F-1226-9C60-0050E4C00067"

        let uuid = ObjC.NSUUID(UUIDString: uuidString)

        #expect(runtimeClassName(of: uuid.asObject) == "__NSConcreteUUID")
        #expect(uuid.UUIDString.asString == uuidString)
    }

    @Test func explicitInitWithMatchesTheImplicitOne() {
        let uuidString = "68753A44-4D6F-1226-9C60-0050E4C00067"

        let uuid = ObjC.NSUUID.initWithUUIDString(uuidString)

        #expect(uuid.UUIDString.asString == uuidString)
    }

    @Test func classNameThatDoesNotExistResolvesToNothing() {
        let missing = DynamicObject(className: "NoSuchClassExistsAnywhere")

        #expect(missing.asAnyObject == nil)
    }
}

// MARK: - Class methods and properties

@Suite("DynamicObject members")
struct DynamicObjectMemberTests {

    @Test func classMethodReturnsAnInstance() {
        let uuid = ObjC.NSUUID.UUID()

        #expect(runtimeClassName(of: uuid.asObject) == "__NSConcreteUUID")
    }

    @Test func multiArgumentClassMethodPassesEveryArgument() {
        let name = "Dummy"
        let reason = "Testing"
        let userInfo = ["Foo": "Bar"] as NSDictionary

        let exception = ObjC.NSException.exceptionWithName(name, reason: reason, userInfo: userInfo)

        #expect(runtimeClassName(of: exception.asObject) == "NSException")
        #expect(exception.name.asString == name)
        #expect(exception.reason.asString == reason)
        #expect(exception.userInfo.asDictionary == userInfo)
    }

    @Test func propertyReadsAndWrites() {
        let components = ObjC.NSURLComponents.componentsWithString("https://example.com/")
        #expect(components.host.asString == "example.com")

        components.host = "example2.com"
        #expect(components.host.asString == "example2.com")

        let queryItems = [NSURLQueryItem(name: "foo", value: "bar")] as NSArray
        components.queryItems = queryItems
        #expect(components.queryItems.asArray == queryItems)
        #expect(components.URL == NSURL(string: "https://example2.com/?foo=bar"))
    }

    @Test func numericPropertyWrite() {
        let progress = ObjC.NSProgress.progressWithTotalUnitCount(100)

        progress.completedUnitCount = 50

        #expect(progress.fractionCompleted == 0.5)
    }

    /// `isSuspended` is written through `setSuspended:`, not `setIsSuspended:`.
    @Test func booleanPropertyWithIsPrefixUsesTheConventionalSetter() {
        let queue = ObjC.NSOperationQueue()
        #expect(queue.isSuspended == false)

        queue.isSuspended = true

        #expect(queue.isSuspended == true)
    }

    /// All three spellings have to produce the selector `stringFromDate:`.
    @Test func argumentLabelsRebuildTheSameSelector() {
        let formatter = ObjC.NSDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = Date()

        let joined = formatter.stringFromDate(date).asString
        let splitAtLowercase: String? = formatter.stringFrom(date: date)
        let splitAtCapital: String? = formatter.string(fromDate: date)

        #expect(joined == splitAtLowercase)
        #expect(joined == splitAtCapital)
    }

    @Test func argumentLabelsRebuildSelectorsOnClassMethodsToo() {
        let joined = ObjC.NSProgress.progressWithTotalUnitCount(99)
        let split = ObjC.NSProgress.progress(withTotalUnitCount: 99)

        #expect(joined.totalUnitCount.asInt == 99)
        #expect(joined.totalUnitCount.asInt == split.totalUnitCount.asInt)
    }
}

// MARK: - Unwrapping

@Suite("DynamicObject unwrapping")
struct DynamicObjectUnwrappingTests {

    @Test func explicitAccessorsMatchTheNativeAPI() {
        let native = ProcessInfo.processInfo
        let dynamic = ObjC.NSProcessInfo.processInfo

        #expect(dynamic.processIdentifier.asInt32 == native.processIdentifier)
        #expect(dynamic.processorCount.asInt == native.processorCount)
        #expect(dynamic.physicalMemory.asUInt64 == native.physicalMemory)
        #expect(dynamic.processName.asString == native.processName)
        #expect(dynamic.arguments.asArray == native.arguments as NSArray)
        #expect(abs((dynamic.systemUptime.asDouble ?? 0) - native.systemUptime) < 1)
    }

    /// A type annotation on the destination picks the generic overload, so no
    /// explicit accessor is needed.
    @Test func annotatedDestinationUnwrapsImplicitly() {
        let native = ProcessInfo.processInfo
        let dynamic = ObjC.NSProcessInfo.processInfo

        let processorCount: Int? = dynamic.processorCount
        let physicalMemory: UInt64? = dynamic.physicalMemory
        let processName: String? = dynamic.processName
        let arguments: [String]? = dynamic.arguments

        #expect(processorCount == native.processorCount)
        #expect(physicalMemory == native.physicalMemory)
        #expect(processName == native.processName)
        #expect(arguments == native.arguments)
    }

    /// A struct return is copied out of the invocation's buffer by layout, so a
    /// locally redeclared shape works as long as size and alignment agree.
    @Test func structReturnUnwrapsByLayout() {
        struct OperatingSystemVersionShape {
            var majorVersion: Int
            var minorVersion: Int
            var patchVersion: Int
        }

        let native = ProcessInfo.processInfo.operatingSystemVersion
        let dynamic: OperatingSystemVersionShape? =
            ObjC.NSProcessInfo.processInfo.operatingSystemVersion.asInferred()

        #expect(dynamic?.majorVersion == native.majorVersion)
        #expect(dynamic?.minorVersion == native.minorVersion)
        #expect(dynamic?.patchVersion == native.patchVersion)
    }

    /// A layout that does not match the declared return type yields `nil`
    /// rather than a plausible-looking wrong value.
    @Test func mismatchedLayoutRefusesToReinterpret() {
        // `processorCount` returns NSUInteger (8 bytes); Int8 is 1.
        let wrongWidth: Int8? = ObjC.NSProcessInfo.processInfo.processorCount.asInt8

        #expect(wrongWidth == nil)
    }

    @Test func wrapperItselfIsNotUnwrappedWhenTheDestinationIsAnObject() {
        let formatter: NSObject? = ObjC.NSDateFormatter()

        #expect(runtimeClassName(of: formatter) == "NSDateFormatter")
    }

    @Test func wrapperArgumentStandsForTheObjectItHolds() {
        let formatter = ObjC.NSDateFormatter()
        formatter.dateFormat = ObjC("yyyy-MM-dd HH:mm:ss")
        let date = ObjC.NSDate(timeIntervalSince1970: 1_600_000_000)

        // The date wrapper is passed straight through as an argument.
        let text: String? = formatter.stringFromDate(date)
        let roundTripped: Date? = formatter.dateFromString(text)

        #expect(roundTripped == date.asInferred())
    }
}

// MARK: - Core Graphics accessors

// Upstream offered these only under `canImport(UIKit)`, so on macOS a struct
// return like `NSSize` had no accessor at all.
#if canImport(CoreGraphics)
@Suite("DynamicObject Core Graphics accessors")
struct DynamicObjectCoreGraphicsTests {

    @Test func sizeReturnUnwraps() {
        let boxed = NSValue(size: CGSize(width: 3, height: 4))

        let size = ObjC(boxed).sizeValue.asCGSize

        #expect(size == CGSize(width: 3, height: 4))
    }

    @Test func pointReturnUnwraps() {
        let boxed = NSValue(point: CGPoint(x: 5, y: 6))

        let point = ObjC(boxed).pointValue.asCGPoint

        #expect(point == CGPoint(x: 5, y: 6))
    }

    @Test func rectReturnUnwraps() {
        let boxed = NSValue(rect: CGRect(x: 1, y: 2, width: 3, height: 4))

        let rect = ObjC(boxed).rectValue.asCGRect

        #expect(rect == CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}
#endif

// MARK: - Blocks

@Suite("DynamicObject block arguments")
struct DynamicObjectBlockTests {

    @Test func blockPassedAsAnArgumentRuns() async {
        typealias VoidBlock = @convention(block) () -> Void

        await confirmation("block runs") { blockRan in
            let operation = ObjC.NSBlockOperation.blockOperationWithBlock({
                blockRan()
            } as VoidBlock)

            // `start()` runs a non-concurrent operation synchronously on this
            // thread, so no run loop has to be pumped for this to complete.
            operation.start()
        }
    }

    @Test func blockAssignedToAPropertyRuns() async {
        typealias VoidBlock = @convention(block) () -> Void

        await confirmation("cancellation handler runs") { handlerRan in
            let progress = ObjC.NSProgress.progressWithTotalUnitCount(100)
            let handlerFinished = DispatchSemaphore(value: 0)

            progress.cancellationHandler = {
                handlerRan()
                handlerFinished.signal()
            } as VoidBlock
            progress.cancel()

            #expect(handlerFinished.wait(timeout: .now() + .seconds(5)) == .success)
        }
    }
}

// MARK: - Failure propagation

@Suite("DynamicObject failure propagation")
struct DynamicObjectFailureTests {

    @Test func unrecognizedSelectorBecomesAnErrorRatherThanACrash() {
        let failed = ObjC.NSDateFormatter().thisMethodDoesNotExist()

        #expect(failed.isError)
        #expect(failed.asObject is Error)
    }

    @Test func chainingOnAFailureReturnsTheSameFailure() {
        let failed = ObjC.NSDateFormatter().thisMethodDoesNotExist()

        let chained = failed.stillDoesNotExist(123).norDoesThisProperty

        #expect(chained === failed)
    }

    @Test func wrappedNilResolvesToNothing() {
        #expect(ObjC.nil.asObject == nil)
    }

    @Test func chainingOnWrappedNilReturnsTheSharedNil() {
        let chained = ObjC.nil.anyMethodAtAll(123).anyPropertyAtAll

        #expect(chained === ObjC.nil)
    }

    /// The shared `nil` is handed out repeatedly, so nothing may write to it.
    @Test func chainingThroughWrappedNilLeavesItUnchanged() {
        _ = ObjC.nil.someMethod(1).someProperty
        _ = ObjC.nil.anotherMethod()

        #expect(ObjC.nil.isError == false)
        #expect(ObjC.nil.asObject == nil)
    }

    @Test func assigningNilClearsTheProperty() {
        let formatter = ObjC.NSDateFormatter()

        formatter.dateFormat = ObjC("yyyy-MM-dd HH:mm:ss")
        #expect(formatter.stringFromDate(Date()).asString?.isEmpty == false)

        formatter.dateFormat = .nil
        #expect(formatter.stringFromDate(Date()).asString?.isEmpty == true)

        formatter.dateFormat = ObjC("yyyy-MM-dd HH:mm:ss")
        #expect(formatter.stringFromDate(Date()).asString?.isEmpty == false)

        formatter.dateFormat = nil as String?
        #expect(formatter.stringFromDate(Date()).asString?.isEmpty == true)
    }

    /// A selector taking arguments, reached with none supplied.
    ///
    /// Upstream wrote the argument loop as `0 ..< numberOfArguments - 2` and
    /// indexed an empty array with it, so this trapped with "Index out of
    /// range". The call is now refused and recorded as an error instead.
    @Test func selectorNeedingArgumentsIsRefusedInsteadOfTrapping() {
        let dictionary = NSMutableDictionary()

        // A member name may legitimately carry colons — `init(_:memberName:)`
        // is public — which is how the counts come apart.
        let wrapper = DynamicObject(dictionary, memberName: "setObject:forKey:")
        let resolved = wrapper.asAnyObject

        #expect(wrapper.isError)
        #expect(resolved is Error)
        #expect(dictionary.count == 0)
    }

    @Test func argumentCountMismatchDescribesBothCounts() {
        let error = RuntimeInvocationError.argumentCountMismatch(
            selectorName: "setObject:forKey:",
            expectedCount: 2,
            providedCount: 0
        )

        #expect(error.description.contains("setObject:forKey:"))
        #expect(error.description.contains("2"))
        #expect(error.description.contains("0"))
    }

    @Test func unrecognizedSelectorErrorBridgesToNSError() {
        let error = RuntimeInvocationError.unrecognizedSelector(
            className: "NSDateFormatter",
            selectorName: "nope"
        )
        let bridged = error as NSError

        #expect(bridged.domain == "ObjCRuntimeToolbox.RuntimeInvocation")
        #expect(bridged.code == 404)
        #expect(bridged.localizedDescription.contains("nope"))
    }
}

// MARK: - Reaching genuinely unavailable API

@Suite("DynamicObject reaching unavailable API")
struct DynamicObjectHiddenAPITests {

    /// `NSInvocation` is unavailable to Swift, which makes it a fair test of
    /// the whole point of this type: driving it through itself.
    @Test func drivesNSInvocationItself() {
        let selector = NSSelectorFromString("lowercaseString")
        let target = NSString("ABC")

        let methodSignature: NSObject? = ObjC(target).methodSignatureForSelector(selector)
        let invocation = ObjC.NSInvocation.invocationWithMethodSignature(methodSignature)
        invocation.selector = selector
        invocation.invokeWithTarget(target)

        var result: NSString?
        withUnsafeMutablePointer(to: &result) { pointer in
            invocation.getReturnValue(pointer)
        }

        #expect(result == "abc")
        if let result {
            // `getReturnValue:` transfers no ownership; balance the release the
            // compiler emits for the value it just saw appear.
            _ = Unmanaged.passRetained(result).takeUnretainedValue()
        }
    }

    @Test func drivesNSInvocationWithMultipleArguments() {
        let selector = NSSelectorFromString("stringByPaddingToLength:withString:startingAtIndex:")
        let target = NSString("ABC")

        let methodSignature: NSObject? = ObjC(target).methodSignatureForSelector(selector)
        let invocation = ObjC.NSInvocation.invocationWithMethodSignature(methodSignature)
        invocation.selector = selector

        let length = 6
        let padding = "0123" as NSString
        let startIndex = 1
        withUnsafePointer(to: length) { invocation.setArgument($0, atIndex: 2) }
        withUnsafePointer(to: padding) { invocation.setArgument($0, atIndex: 3) }
        withUnsafePointer(to: startIndex) { invocation.setArgument($0, atIndex: 4) }
        invocation.invokeWithTarget(target)

        var result: NSString?
        withUnsafeMutablePointer(to: &result) { pointer in
            invocation.getReturnValue(pointer)
        }

        #expect(result == "ABC123")
        if let result {
            _ = Unmanaged.passRetained(result).takeUnretainedValue()
        }
    }
}

// MARK: - Foundation type bridging

@Suite("FoundationTypeBridging")
struct FoundationTypeBridgingTests {

    @Test func bridgesSwiftValuesToObjects() {
        #expect(FoundationTypeBridging.bridgedToObjectiveC("text") is NSString)
        #expect(FoundationTypeBridging.bridgedToObjectiveC(Date()) is NSDate)
        #expect(FoundationTypeBridging.bridgedToObjectiveC(UUID()) is NSUUID)
        #expect(FoundationTypeBridging.bridgedToObjectiveC([1, 2, 3]) is NSArray)
    }

    @Test func bridgesObjectsToSwiftValues() {
        #expect(FoundationTypeBridging.bridgedToSwift(NSString("text")) is String)
        #expect(FoundationTypeBridging.bridgedToSwift(NSDate()) is Date)
        #expect(FoundationTypeBridging.bridgedToSwift(NSUUID()) is UUID)
    }

    @Test func leavesUnpairedValuesAlone() {
        #expect(FoundationTypeBridging.bridgedToObjectiveC(42) == nil)
        #expect(FoundationTypeBridging.bridgedToObjectiveC(nil) == nil)
        #expect(FoundationTypeBridging.bridgedToSwift(NSObject()) == nil)
    }

    @Test func pairsResolveInBothDirections() {
        #expect(FoundationTypeBridging.objectiveCType(forSwiftType: String.self) == NSString.self)
        #expect(FoundationTypeBridging.swiftType(forObjectiveCType: NSString.self) == String.self)
        #expect(FoundationTypeBridging.counterpartType(of: URL.self) == NSURL.self)
        #expect(FoundationTypeBridging.counterpartType(of: NSURL.self) == URL.self)
        #expect(FoundationTypeBridging.counterpartType(of: NSObject.self) == nil)
    }
}

#endif
