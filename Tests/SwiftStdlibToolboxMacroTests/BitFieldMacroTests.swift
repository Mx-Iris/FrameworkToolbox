import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

// The getter hands the property's type to `SwiftStdlibToolbox._BitFieldAccess`
// and the compiler picks the conversion, so these snapshots only show the call.
// That each type reads the right value, and that an unsupported type is an
// error on the property's line, is covered by real compilation: `BitFieldTests`
// in `SwiftStdlibToolboxTests`, and the client targets.
@Suite(.macros(["BitField": BitFieldMacro.self]))
struct BitFieldMacroTests {

    // MARK: - What is generated

    @Test func readsASinglePositionAsAOneBitRange() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient: Bool
            }
            """
        } expansion: {
            """
            struct Flags {
                let rawValue: UInt16
                var isResilient: Bool {
                    get {
                        #sourceLocation(file: "Test.swift", line: 5)
                        SwiftStdlibToolbox._BitFieldAccess.value(of: self.rawValue, bits: 1 ..< 2, as: (Bool).self)
                        #sourceLocation()
                    }
                }
            }
            """
        }
    }

    @Test func leavesTheDocumentationAttributesAndAccessOfThePropertyInPlace() {
        assertMacro {
            """
            public struct Flags {
                public let rawValue: UInt16

                /// The special protocol, or `nil` for a value this reader does not know.
                @available(macOS 14, *)
                @BitField(bits: 2..<8)
                public var specialProtocolKind: SpecialProtocolKind?
            }
            """
        } expansion: {
            """
            public struct Flags {
                public let rawValue: UInt16

                /// The special protocol, or `nil` for a value this reader does not know.
                @available(macOS 14, *)
                public var specialProtocolKind: SpecialProtocolKind? {
                    get {
                        #sourceLocation(file: "Test.swift", line: 7)
                        SwiftStdlibToolbox._BitFieldAccess.value(of: self.rawValue, bits: 2 ..< 8, as: (SpecialProtocolKind?).self)
                        #sourceLocation()
                    }
                }
            }
            """
        }
    }

    @Test func passesTheDefaultThroughAsWritten() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt32

                @BitField(bits: 0..<5, default: ContextDescriptorKind.unknown)
                var kind: ContextDescriptorKind
            }
            """
        } expansion: {
            """
            struct Flags {
                let rawValue: UInt32
                var kind: ContextDescriptorKind {
                    get {
                        #sourceLocation(file: "Test.swift", line: 5)
                        SwiftStdlibToolbox._BitFieldAccess.value(of: self.rawValue, bits: 0 ..< 5, as: (ContextDescriptorKind).self, default: ContextDescriptorKind.unknown)
                        #sourceLocation()
                    }
                }
            }
            """
        }
    }

    @Test func doesNotCheckATypeItCannotRecognize() {
        // A typealias could be any width; the runtime checks what the macro
        // cannot see.
        assertMacro {
            """
            struct Flags {
                typealias Count = UInt8
                let rawValue: UInt32

                @BitField(bits: 0..<16)
                var count: Count
            }
            """
        } expansion: {
            """
            struct Flags {
                typealias Count = UInt8
                let rawValue: UInt32
                var count: Count {
                    get {
                        #sourceLocation(file: "Test.swift", line: 6)
                        SwiftStdlibToolbox._BitFieldAccess.value(of: self.rawValue, bits: 0 ..< 16, as: (Count).self)
                        #sourceLocation()
                    }
                }
            }
            """
        }
    }

    // MARK: - The property it is attached to

    // An accessor macro can only be attached to a property or a subscript; the
    // compiler turns away anything else before the macro runs.
    @Test func rejectsASubscript() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                subscript(position: Int) -> Bool
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                ┬─────────────────
                ╰─ 🛑 '@BitField' must be applied to a property
                subscript(position: Int) -> Bool
            }
            """
        }
    }

    @Test func offersVarInPlaceOfLet() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                let isResilient: Bool
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                let isResilient: Bool
                ┬──
                ╰─ 🛑 a bit field is computed from 'rawValue', so it is declared with 'var'
                   ✏️ replace 'let' with 'var'
            }
            """
        } fixes: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient: Bool
            }
            """
        } expansion: {
            """
            struct Flags {
                let rawValue: UInt16
                var isResilient: Bool {
                    get {
                        #sourceLocation(file: "Test.swift", line: 5)
                        SwiftStdlibToolbox._BitFieldAccess.value(of: self.rawValue, bits: 1 ..< 2, as: (Bool).self)
                        #sourceLocation()
                    }
                }
            }
            """
        }
    }

    @Test func offersToRemoveAnInitialValue() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient: Bool = false
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient: Bool = false
                                      ┬──────
                                      ╰─ 🛑 a bit field has no storage of its own; its value is read from 'rawValue'
                                         ✏️ remove the initial value
            }
            """
        } fixes: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient: Bool
            }
            """
        } expansion: {
            """
            struct Flags {
                let rawValue: UInt16
                var isResilient: Bool {
                    get {
                        #sourceLocation(file: "Test.swift", line: 5)
                        SwiftStdlibToolbox._BitFieldAccess.value(of: self.rawValue, bits: 1 ..< 2, as: (Bool).self)
                        #sourceLocation()
                    }
                }
            }
            """
        }
    }

    // The compiler reports each error on the property's name. The harness draws
    // both at the top instead: swift-syntax expands the macro on a rewritten
    // copy of a declaration that has accessors, and the copy's positions are
    // not the file's.
    @Test func rejectsAccessorsOfItsOwn() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient: Bool {
                    rawValue & 2 != 0
                }

                @BitField(bits: 2)
                var isUnique: Bool {
                    didSet {}
                }
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16
                              ├─ 🛑 '@BitField' writes the getter itself; remove this property's accessors
                              ╰─ 🛑 '@BitField' writes the getter itself; remove this property's accessors

                @BitField(bits: 1)
                var isResilient: Bool {
                    rawValue & 2 != 0
                }

                @BitField(bits: 2)
                var isUnique: Bool {
                    didSet {}
                }
            }
            """
        }
    }

    @Test func requiresTheTypeWrittenOut() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient
                    ┬──────────
                    ╰─ 🛑 '@BitField' needs the property's type written out: the type decides how the bits are read
            }
            """
        }
    }

    @Test func rejectsAStaticProperty() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                static var isResilient: Bool
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                static var isResilient: Bool
                ┬─────
                ╰─ 🛑 a bit field reads the 'rawValue' of an instance, so it cannot be 'static'
            }
            """
        }
    }

    @Test func rejectsSeveralPropertiesInOneDeclaration() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                var isResilient: Bool, isUnique: Bool
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 1)
                ╰─ 🛑 accessor macro can only be applied to a single variable
                var isResilient: Bool, isUnique: Bool
            }
            """
        }
    }

    // MARK: - The bits

    @Test func rejectsBitsThatAreNotLiterals() {
        assertMacro {
            """
            struct Flags {
                static let firstKindBit = 0
                let rawValue: UInt16

                @BitField(bits: Self.firstKindBit..<5)
                var kind: Kind?
            }
            """
        } diagnostics: {
            """
            struct Flags {
                static let firstKindBit = 0
                let rawValue: UInt16

                @BitField(bits: Self.firstKindBit..<5)
                                ┬────────────────────
                                ╰─ 🛑 invalid value for argument 'bits', expected a bit position or a half-open range of them written as integer literals, such as '5' or '2..<8'
                var kind: Kind?
            }
            """
        }
    }

    @Test func rejectsANegativePosition() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: -1)
                var isResilient: Bool
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: -1)
                                ┬─
                                ╰─ 🛑 invalid value for argument 'bits', bit position -1 is negative; bit 0 is the least significant
                var isResilient: Bool
            }
            """
        }
    }

    @Test func rejectsARangeWithNoBits() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 8..<8)
                var kind: Kind?

                @BitField(bits: 8..<2)
                var otherKind: Kind?
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 8..<8)
                                ┬────
                                ╰─ 🛑 invalid value for argument 'bits', 8..<8 holds no bits
                var kind: Kind?

                @BitField(bits: 8..<2)
                                ┬────
                                ╰─ 🛑 invalid value for argument 'bits', 8..<2 holds no bits
                var otherKind: Kind?
            }
            """
        }
    }

    @Test func rejectsABoolWiderThanOneBit() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 2..<4)
                var isResilient: Bool
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt16

                @BitField(bits: 2..<4)
                                ┬────
                                ╰─ 🛑 a 'Bool' bit field reads one bit, but bits 2..<4 are 2 bits wide
                var isResilient: Bool
            }
            """
        }
    }

    @Test func rejectsAnIntegerNarrowerThanTheBits() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt32

                @BitField(bits: 0..<16)
                var count: Swift.UInt8
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt32

                @BitField(bits: 0..<16)
                                ┬─────
                                ╰─ 🛑 bits 0..<16 are 16 bits wide, more than 'Swift.UInt8' holds
                var count: Swift.UInt8
            }
            """
        }
    }

    @Test func checksIntAsSixtyFourBitsWide() {
        assertMacro {
            """
            struct Flags {
                let rawValue: UInt128

                @BitField(bits: 0..<64)
                var low: Int

                @BitField(bits: 0..<65)
                var tooWide: Int
            }
            """
        } diagnostics: {
            """
            struct Flags {
                let rawValue: UInt128

                @BitField(bits: 0..<64)
                var low: Int

                @BitField(bits: 0..<65)
                                ┬─────
                                ╰─ 🛑 bits 0..<65 are 65 bits wide, more than 'Int' holds
                var tooWide: Int
            }
            """
        }
    }
}
