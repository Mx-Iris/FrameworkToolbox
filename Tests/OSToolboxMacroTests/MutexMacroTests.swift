import MacroTesting
import Testing

@testable import OSToolboxMacros

@Suite(.macros(["Mutex": MutexMacro.self]))
struct MutexMacroTests {

    @Test func basicProperty() {
        assertMacro {
            """
            @Mutex
            var counter: Int = 0
            """
        } expansion: {
            """
            var counter: Int {
                get {
                    _counter.withLock {
                        $0
                    }
                }
                set {
                    _counter.withLock { (value: inout Int ) -> Void in
                        value = newValue
                    }
                }
                _modify {
                    let valuePointer = _counter._unsafeLock()
                    defer {
                        _counter._unsafeUnlock()
                    }
                    yield &valuePointer.pointee
                }
            }

            private let _counter = OSToolbox.Mutex<Int >(0)
            """
        }
    }

    @Test func stringProperty() {
        assertMacro {
            """
            @Mutex
            var name: String = ""
            """
        } expansion: {
            """
            var name: String {
                get {
                    _name.withLock {
                        $0
                    }
                }
                set {
                    _name.withLock { (value: inout String ) -> Void in
                        value = newValue
                    }
                }
                _modify {
                    let valuePointer = _name._unsafeLock()
                    defer {
                        _name._unsafeUnlock()
                    }
                    yield &valuePointer.pointee
                }
            }

            private let _name = OSToolbox.Mutex<String >("")
            """
        }
    }

    @Test func optionalProperty() {
        assertMacro {
            """
            @Mutex
            var value: String? = nil
            """
        } expansion: {
            """
            var value: String? {
                get {
                    _value.withLock {
                        $0
                    }
                }
                set {
                    _value.withLock { (value: inout String? ) -> Void in
                        value = newValue
                    }
                }
                _modify {
                    let valuePointer = _value._unsafeLock()
                    defer {
                        _value._unsafeUnlock()
                    }
                    yield &valuePointer.pointee
                }
            }

            private let _value = OSToolbox.Mutex<String? >(nil)
            """
        }
    }

    @Test func implicitlyUnwrappedOptional() {
        assertMacro {
            """
            @Mutex
            var value: String!
            """
        } expansion: {
            """
            var value: String! {
                get {
                    _value.withLock {
                        $0!
                    }
                }
                set {
                    _value.withLock { (value: inout String?) -> Void in
                        value = newValue
                    }
                }
            }

            private let _value = OSToolbox.Mutex<String?>(nil)
            """
        }
    }

    @Test func arrayProperty() {
        assertMacro {
            """
            @Mutex
            var items: [String] = []
            """
        } expansion: {
            """
            var items: [String] {
                get {
                    _items.withLock {
                        $0
                    }
                }
                set {
                    _items.withLock { (value: inout [String] ) -> Void in
                        value = newValue
                    }
                }
                _modify {
                    let valuePointer = _items._unsafeLock()
                    defer {
                        _items._unsafeUnlock()
                    }
                    yield &valuePointer.pointee
                }
            }

            private let _items = OSToolbox.Mutex<[String] >([])
            """
        }
    }

    /// Pins the module that qualifies `WeakBox` in the generated storage.
    ///
    /// `weak` is the only shape whose expansion names a type from another file
    /// by its module, so it is the only one that breaks when `WeakBox` moves
    /// between targets — as it did when `OSToolbox` was split out of
    /// `SwiftStdlibToolbox`. Every other shape spells out `Mutex<...>` alone
    /// and would keep compiling through such a move.
    @Test func weakProperty() {
        assertMacro {
            """
            @Mutex
            weak var delegate: AnyObject?
            """
        } expansion: {
            """
            weak var delegate: AnyObject? {
                get {
                    _delegate.withLock {
                        $0.value
                    }
                }
                set {
                    _delegate.withLock { (weakBox: inout OSToolbox.WeakBox<AnyObject>) -> Void in
                        weakBox.value = newValue
                    }
                }
            }

            private let _delegate = OSToolbox.Mutex(OSToolbox.WeakBox<AnyObject>(nil))
            """
        }
    }

    @Test func staticProperty() {
        assertMacro {
            """
            @Mutex
            static var counter: Int = 0
            """
        } expansion: {
            """
            static var counter: Int {
                get {
                    _counter.withLock {
                        $0
                    }
                }
                set {
                    _counter.withLock { (value: inout Int ) -> Void in
                        value = newValue
                    }
                }
                _modify {
                    let valuePointer = _counter._unsafeLock()
                    defer {
                        _counter._unsafeUnlock()
                    }
                    yield &valuePointer.pointee
                }
            }

            private static let _counter = OSToolbox.Mutex<Int >(0)
            """
        }
    }

    // Without a type annotation the compiler infers the property's type from
    // the initial value, which it keeps for inference once the accessors are
    // added, and the storage infers its generic argument the same way. The
    // harness drops the initializer from its output, which the compiler does
    // not do.
    @Test func inferredType() {
        assertMacro {
            """
            @Mutex
            var counter = 0
            """
        } expansion: {
            """
            var counter {
                get {
                    _counter.withLock {
                        $0
                    }
                }
                set {
                    _counter.withLock {
                        $0 = newValue
                    }
                }
                _modify {
                    let valuePointer = _counter._unsafeLock()
                    defer {
                        _counter._unsafeUnlock()
                    }
                    yield &valuePointer.pointee
                }
            }

            private let _counter = OSToolbox.Mutex(0)
            """
        }
    }

    @Test func weakPropertyStillNeedsAType() {
        assertMacro {
            """
            @Mutex
            weak var delegate = object
            """
        } diagnostics: {
            // Reported once by each of the macro's two roles, as every other
            // rejection of the lock macros is.
            """
            @Mutex
            ┬─────
            ├─ 🛑 @Mutex requires an explicit type annotation.
            ╰─ 🛑 @Mutex requires an explicit type annotation.
            weak var delegate = object
            """
        }
    }
}
