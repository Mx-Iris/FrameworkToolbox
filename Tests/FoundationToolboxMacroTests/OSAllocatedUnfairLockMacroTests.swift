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
            }

            private let _counter = OSAllocatedUnfairLock<Int >(initialState: 0)
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
            }

            private let _name = OSAllocatedUnfairLock<String >(initialState: "hello")
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
        }
    }
}
