import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

// The reporting half of the member checks. The harness maps a macro name
// straight to one implementation, so which overload the compiler would choose
// cannot be tested here — `EquatableMemberChecks.swift` in
// `SwiftStdlibToolboxClient` covers that with real compilation. These tests pin
// what the caller sees once the compiler has chosen this one.
@Suite(.macros([
    "_EquatableMemberCheck": UncomparableMemberMacro.self,
    "_HashableMemberCheck": UncomparableMemberMacro.self,
]))
struct UncomparableMemberMacroTests {
    @Test func reportsTheWrittenTypeOnTheMember() {
        assertMacro {
            """
            struct Cache {
                @_EquatableMemberCheck(type: [String: Any].self)
                var storage: [String: Any] = [:]
            }
            """
        } diagnostics: {
            """
            struct Cache {
                @_EquatableMemberCheck(type: [String: Any].self)
                var storage: [String: Any] = [:]
                             ┬────────────
                             ╰─ 🛑 '[String: Any]' does not conform to 'Equatable', so '@Equatable' cannot compare 'storage'
                                ✏️ Apply '@EquatableIgnored' to leave 'storage' out of the comparison
            }
            """
        } fixes: {
            """
            struct Cache {
                @EquatableIgnored
                var storage: [String: Any] = [:]
            }
            """
        } expansion: {
            """
            struct Cache {
                @EquatableIgnored
                var storage: [String: Any] = [:]
            }
            """
        }
    }

    @Test func reportsAnInferredTypeByThePropertyName() {
        assertMacro {
            """
            struct Cache {
                @_EquatableMemberCheck(initialValue: Box())
                var box = Box()
            }
            """
        } diagnostics: {
            """
            struct Cache {
                @_EquatableMemberCheck(initialValue: Box())
                var box = Box()
                    ┬──
                    ╰─ 🛑 the type of 'box' does not conform to 'Equatable', so '@Equatable' cannot compare it
                       ✏️ Apply '@EquatableIgnored' to leave 'box' out of the comparison
            }
            """
        } fixes: {
            """
            struct Cache {
                @EquatableIgnored
                var box = Box()
            }
            """
        } expansion: {
            """
            struct Cache {
                @EquatableIgnored
                var box = Box()
            }
            """
        }
    }

    @Test func keepsTheMembersOwnAttributesInTheFix() {
        assertMacro {
            """
            struct Row {
                @Clamped @_EquatableMemberCheck(type: (@Sendable () -> Void).self) var onTap: @Sendable () -> Void
            }
            """
        } diagnostics: {
            """
            struct Row {
                @Clamped @_EquatableMemberCheck(type: (@Sendable () -> Void).self) var onTap: @Sendable () -> Void
                                                                                              ┬───────────────────
                                                                                              ╰─ 🛑 '@Sendable () -> Void' does not conform to 'Equatable', so '@Equatable' cannot compare 'onTap'
                                                                                                 ✏️ Apply '@EquatableIgnored' to leave 'onTap' out of the comparison
            }
            """
        } fixes: {
            """
            struct Row {
                @Clamped @EquatableIgnored var onTap: @Sendable () -> Void
            }
            """
        } expansion: {
            """
            struct Row {
                @Clamped @EquatableIgnored var onTap: @Sendable () -> Void
            }
            """
        }
    }

    @Test func explainsTheHashableRequirement() {
        assertMacro {
            """
            struct Tagged {
                @_HashableMemberCheck(type: MemberCheckPoint.self)
                let point: MemberCheckPoint
            }
            """
        } diagnostics: {
            """
            struct Tagged {
                @_HashableMemberCheck(type: MemberCheckPoint.self)
                let point: MemberCheckPoint
                           ┬───────────────
                           ╰─ 🛑 'MemberCheckPoint' does not conform to 'Hashable', so the 'hash(into:)' that '@Equatable' writes for a Hashable type cannot include 'point'
                              ✏️ Apply '@EquatableIgnored' to leave 'point' out of the comparison
            }
            """
        } fixes: {
            """
            struct Tagged {
                @EquatableIgnored
                let point: MemberCheckPoint
            }
            """
        } expansion: {
            """
            struct Tagged {
                @EquatableIgnored
                let point: MemberCheckPoint
            }
            """
        }
    }
}
