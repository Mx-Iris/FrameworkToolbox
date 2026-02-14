import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

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
            }

            private let _counter = Mutex<Int >(0)
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
            }

            private let _name = Mutex<String >("")
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
            }

            private let _value = Mutex<String? >(nil)
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

            private let _value = Mutex<String?>(nil)
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
            }

            private let _items = Mutex<[String] >([])
            """
        }
    }
}
