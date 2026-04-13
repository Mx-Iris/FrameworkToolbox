import MacroTesting
import Testing

@testable import FoundationToolboxMacros

@Suite(.macros(["OSAllocatedUnfairLock": OSAllocatedUnfairLockMacro.self]))
struct OSAllocatedUnfairLockMacroTests {

    @Test func basicProperty() {
        assertMacro {
            """
            @OSAllocatedUnfairLock
            var counter: Int = 0
            """
        } expansion: {
            #if OSAllocatedUnfairLockUnsafeModify
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

            private let _counter = OSAllocatedUnfairLock<Int >(initialState: 0)
            """
            #else
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
            }

            private let _counter = OSAllocatedUnfairLock<Int >(initialState: 0)
            """
            #endif
        }
    }

    @Test func stringProperty() {
        assertMacro {
            """
            @OSAllocatedUnfairLock
            var name: String = "hello"
            """
        } expansion: {
            #if OSAllocatedUnfairLockUnsafeModify
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

            private let _name = OSAllocatedUnfairLock<String >(initialState: "hello")
            """
            #else
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
            }

            private let _name = OSAllocatedUnfairLock<String >(initialState: "hello")
            """
            #endif
        }
    }

    @Test func implicitlyUnwrappedOptional() {
        assertMacro {
            """
            @OSAllocatedUnfairLock
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

            private let _value = OSAllocatedUnfairLock<String?>(initialState: nil)
            """
        }
    }

    @Test func arrayProperty() {
        assertMacro {
            """
            @OSAllocatedUnfairLock
            var items: [String] = []
            """
        } expansion: {
            #if OSAllocatedUnfairLockUnsafeModify
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

            private let _items = OSAllocatedUnfairLock<[String] >(initialState: [])
            """
            #else
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
            }

            private let _items = OSAllocatedUnfairLock<[String] >(initialState: [])
            """
            #endif
        }
    }

    @Test func staticProperty() {
        assertMacro {
            """
            @OSAllocatedUnfairLock
            static var counter: Int = 0
            """
        } expansion: {
            #if OSAllocatedUnfairLockUnsafeModify
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

            private static let _counter = OSAllocatedUnfairLock<Int >(initialState: 0)
            """
            #else
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
            }

            private static let _counter = OSAllocatedUnfairLock<Int >(initialState: 0)
            """
            #endif
        }
    }
}
