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

            private let _counter = os.OSAllocatedUnfairLock<Int >(initialState: 0)
            """
        }
    }

    @Test func stringProperty() {
        assertMacro {
            """
            @OSAllocatedUnfairLock
            var name: String = "hello"
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

            private let _name = os.OSAllocatedUnfairLock<String >(initialState: "hello")
            """
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

            private let _value = os.OSAllocatedUnfairLock<String?>(initialState: nil)
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

            private let _items = os.OSAllocatedUnfairLock<[String] >(initialState: [])
            """
        }
    }

    @Test func staticProperty() {
        assertMacro {
            """
            @OSAllocatedUnfairLock
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

            private static let _counter = os.OSAllocatedUnfairLock<Int >(initialState: 0)
            """
        }
    }
}
