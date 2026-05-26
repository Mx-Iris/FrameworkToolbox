import CoreFoundation
import Foundation
import FrameworkToolbox

extension CFRunLoop {

    public typealias Mode = CFRunLoopMode
    public typealias Source = CFRunLoopSource
    public typealias Observer = CFRunLoopObserver
    public typealias Timer = CFRunLoopTimer
    public typealias RunResult = CFRunLoopRunResult
    public typealias Activity = CFRunLoopActivity
}

extension FrameworkToolbox<CFRunLoop> {

    @inlinable
    public static var current: CFRunLoop {
        CFRunLoopGetCurrent()
    }

    @inlinable
    public static var main: CFRunLoop {
        CFRunLoopGetMain()
    }

    @inlinable
    public func currentMode() -> CFRunLoop.Mode {
        CFRunLoopCopyCurrentMode(base)
    }

    @inlinable
    public func allModes() -> [CFRunLoop.Mode] {
        CFRunLoopCopyAllModes(base)._bridgeToNS().map { CFRunLoop.Mode._from(raw: $0 as! CFString) }
    }

    @inlinable
    public func addCommonMode(_ mode: CFRunLoop.Mode) {
        CFRunLoopAddCommonMode(base, mode)
    }

    @inlinable
    public func nextTimerFireDate(mode: CFRunLoop.Mode) -> CFAbsoluteTime {
        CFRunLoopGetNextTimerFireDate(base, mode)
    }

    @inlinable
    public static func run() {
        CFRunLoopRun()
    }

    @inlinable
    public static func run(in mode: CFRunLoop.Mode, seconds: CFTimeInterval = 0, returnAfterSourceHandled: Bool = true) -> CFRunLoop.RunResult {
        CFRunLoopRunInMode(mode, seconds, returnAfterSourceHandled)
    }

    @inlinable
    public var isWaiting: Bool {
        CFRunLoopIsWaiting(base)
    }

    @inlinable
    public func wakeUp() {
        CFRunLoopWakeUp(base)
    }

    @inlinable
    public func stop() {
        CFRunLoopStop(base)
    }

    @inlinable
    public func perform(mode: CFRunLoop.Mode, block: @escaping () -> Void) {
        CFRunLoopPerformBlock(base, mode._raw, block)
    }

    @inlinable
    public func perform(modes: [CFRunLoop.Mode], block: @escaping () -> Void) {
        let array = CFArray._bridgeFromNS(.init(array: modes.map { $0._raw }))
        CFRunLoopPerformBlock(base, array, block)
    }

    @inlinable
    public func contains(source: CFRunLoop.Source, mode: CFRunLoop.Mode) {
        CFRunLoopContainsSource(base, source, mode)
    }

    @inlinable
    public func add(source: CFRunLoop.Source, mode: CFRunLoop.Mode) {
        CFRunLoopAddSource(base, source, mode)
    }

    @inlinable
    public func remove(source: CFRunLoop.Source, mode: CFRunLoop.Mode) {
        CFRunLoopRemoveSource(base, source, mode)
    }

    @inlinable
    public func contains(observer: CFRunLoop.Observer, mode: CFRunLoop.Mode) {
        CFRunLoopContainsObserver(base, observer, mode)
    }

    @inlinable
    public func add(observer: CFRunLoop.Observer, mode: CFRunLoop.Mode) {
        CFRunLoopAddObserver(base, observer, mode)
    }

    @inlinable
    public func remove(observer: CFRunLoop.Observer, mode: CFRunLoop.Mode) {
        CFRunLoopRemoveObserver(base, observer, mode)
    }

    @inlinable
    public func contains(timer: CFRunLoop.Timer, mode: CFRunLoop.Mode) {
        CFRunLoopContainsTimer(base, timer, mode)
    }

    @inlinable
    public func add(timer: CFRunLoop.Timer, mode: CFRunLoop.Mode) {
        CFRunLoopAddTimer(base, timer, mode)
    }

    @inlinable
    public func remove(timer: CFRunLoop.Timer, mode: CFRunLoop.Mode) {
        CFRunLoopRemoveTimer(base, timer, mode)
    }
}

// MARK: - Source

extension CFRunLoopSource {
    public typealias Context = CFRunLoopSourceContext
    public typealias Context1 = CFRunLoopSourceContext1
}

extension FrameworkToolbox<CFRunLoopSource> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        order: CFIndex,
        context: CFRunLoopSource.Context
    ) -> CFRunLoopSource {
        var context = context
        return CFRunLoopSourceCreate(allocator, order, &context)
    }

    @inlinable
    public var order: CFIndex {
        CFRunLoopSourceGetOrder(base)
    }

    @inlinable
    public func invalidate() {
        CFRunLoopSourceInvalidate(base)
    }

    @inlinable
    public var isValid: Bool {
        CFRunLoopSourceIsValid(base)
    }

    @inlinable
    public var context: CFRunLoopSource.Context {
        var context = CFRunLoopSource.Context()
        CFRunLoopSourceGetContext(base, &context)
        return context
    }

    @inlinable
    public func signal() {
        CFRunLoopSourceSignal(base)
    }
}

// MARK: - Observer

extension CFRunLoopObserver {
    public typealias Context = CFRunLoopObserverContext
    public typealias CallBack = CFRunLoopObserverCallBack
}

extension FrameworkToolbox<CFRunLoopObserver> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        activities: CFRunLoop.Activity,
        repeats: Bool,
        order: CFIndex,
        callout: @escaping CFRunLoopObserver.CallBack,
        context: CFRunLoopObserver.Context
    ) -> CFRunLoopObserver {
        var context = context
        return CFRunLoopObserverCreate(allocator, activities._raw, repeats, order, callout, &context)
    }

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        activities: CFRunLoop.Activity,
        repeats: Bool,
        order: CFIndex,
        block: @escaping (CFRunLoop.Observer?, CFRunLoop.Activity) -> Void
    ) -> CFRunLoopObserver {
        CFRunLoopObserverCreateWithHandler(allocator, activities._raw, repeats, order, block)
    }

    @inlinable
    public var activity: CFRunLoop.Activity {
        let raw = CFRunLoopObserverGetActivities(base)
        return CFRunLoop.Activity._from(raw: raw)
    }

    @inlinable
    public var doesRepeat: Bool {
        CFRunLoopObserverDoesRepeat(base)
    }

    @inlinable
    public var order: CFIndex {
        CFRunLoopObserverGetOrder(base)
    }

    @inlinable
    public func invalidate() {
        CFRunLoopObserverInvalidate(base)
    }

    @inlinable
    public var isValid: Bool {
        CFRunLoopObserverIsValid(base)
    }

    @inlinable
    public var context: CFRunLoopObserver.Context {
        var context = CFRunLoopObserver.Context()
        CFRunLoopObserverGetContext(base, &context)
        return context
    }
}

// MARK: - Timer

extension CFRunLoopTimer {
    public typealias Context = CFRunLoopTimerContext
    public typealias CallBack = CFRunLoopTimerCallBack
}

extension FrameworkToolbox<CFRunLoopTimer> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        fireDate: CFAbsoluteTime,
        interval: CFTimeInterval,
        flags: CFOptionFlags,
        order: CFIndex,
        callout: @escaping CFRunLoopTimer.CallBack,
        context: CFRunLoopTimer.Context
    ) -> CFRunLoopTimer {
        var context = context
        return CFRunLoopTimerCreate(allocator, fireDate, interval, flags, order, callout, &context)
    }

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        fireDate: CFAbsoluteTime,
        interval: CFTimeInterval,
        flags: CFOptionFlags,
        order: CFIndex,
        block: @escaping (CFRunLoop.Timer?) -> Void
    ) -> CFRunLoopTimer {
        CFRunLoopTimerCreateWithHandler(allocator, fireDate, interval, flags, order, block)
    }

    @inlinable
    public var nextFireDate: CFAbsoluteTime {
        get { CFRunLoopTimerGetNextFireDate(base) }
        set { CFRunLoopTimerSetNextFireDate(base, newValue) }
    }

    @inlinable
    public var interval: CFTimeInterval {
        CFRunLoopTimerGetInterval(base)
    }

    @inlinable
    public var doesRepeat: Bool {
        CFRunLoopTimerDoesRepeat(base)
    }

    @inlinable
    public var order: CFIndex {
        CFRunLoopTimerGetOrder(base)
    }

    @inlinable
    public func invalidate() {
        CFRunLoopTimerInvalidate(base)
    }

    @inlinable
    public var isValid: Bool {
        CFRunLoopTimerIsValid(base)
    }

    @inlinable
    public var context: CFRunLoopTimer.Context {
        var context = CFRunLoopTimer.Context()
        CFRunLoopTimerGetContext(base, &context)
        return context
    }

    @inlinable
    public var tolerance: CFTimeInterval {
        get { CFRunLoopTimerGetTolerance(base) }
        set { CFRunLoopTimerSetTolerance(base, newValue) }
    }
}

// MARK: - Raw helpers

extension CFRunLoop.Mode {

    @usableFromInline
    var _raw: CFString {
        #if canImport(Darwin)
        return rawValue
        #else
        return self
        #endif
    }

    @usableFromInline
    static func _from(raw: CFString) -> CFRunLoop.Mode {
        #if canImport(Darwin)
        return .init(rawValue: raw)
        #else
        return raw
        #endif
    }
}

extension CFRunLoop.Activity {

    @usableFromInline
    var _raw: CFOptionFlags {
        #if canImport(Darwin) || swift(>=5.3)
        return rawValue
        #else
        return self
        #endif
    }

    @usableFromInline
    static func _from(raw: CFOptionFlags) -> CFRunLoop.Activity {
        #if canImport(Darwin) || swift(>=5.3)
        return .init(rawValue: raw)
        #else
        return raw
        #endif
    }
}
