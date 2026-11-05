import Foundation
import SwiftStdlibToolbox
import Testing

/// A set that leaves `OptionSet` to the macro, with its positions written out
/// the way a persisted set should write them.
@FlagSet
struct Permissions: Codable, Hashable {
    enum Flag: Int, CaseIterable {
        case read = 0
        case write = 1
        case execute = 5
    }
}

/// A set that declares `OptionSet` itself, so the macro must not add the
/// conformance a second time, with implicit positions in a narrower raw type.
@FlagSet
struct Channels: OptionSet {
    enum Flag: UInt8 {
        case red, green, blue
    }
}

/// Behaviour of `@FlagSet` under the real compiler.
///
/// Every fixture above has to compile before an assertion runs, which is what
/// the expansion snapshots in `Tests/SwiftStdlibToolboxMacroTests/` cannot
/// show: that the generated members satisfy `OptionSet`, and that the
/// conformance is added exactly when the structure does not declare it.
///
/// No `@Test(arguments:)` below names a generated member. Name lookup inside
/// any macro's arguments skips what macros generate — `NameLookupRequests.cpp`
/// in the compiler, to keep expansions from depending on one another — so
/// `arguments: [Permissions.read]` reports that `Permissions` has no member
/// `read`. The arguments are the user-written `Flag` cases instead.
@Suite("@FlagSet")
struct FlagSetTests {

    @Test("each flag is the bit at its case's position", arguments: [
        (Permissions.Flag.read, 1),
        (.write, 2),
        (.execute, 32),
    ] as [(Permissions.Flag, Int)])
    func flagIsTheBitAtItsPosition(flag: Permissions.Flag, rawValue: Int) {
        #expect(Permissions(flag).rawValue == rawValue)
    }

    @Test("each static is the set made from the case of its name")
    func staticsAreTheSetsMadeFromTheirCases() {
        #expect(Permissions.read == Permissions(.read))
        #expect(Permissions.write == Permissions(.write))
        #expect(Permissions.execute == Permissions(.execute))
    }

    @Test("implicit positions count up from zero")
    func implicitPositionsCountUpFromZero() {
        #expect([Channels.red.rawValue, Channels.green.rawValue, Channels.blue.rawValue] == [1, 2, 4])
    }

    @Test("the conformance the macro adds supports the set operations")
    func generatedConformanceSupportsSetOperations() {
        var permissions: Permissions = [.read, .execute]
        #expect(permissions.rawValue == 33)
        #expect(permissions.contains(.read))
        #expect(!permissions.contains(.write))

        permissions.insert(.write)
        permissions.remove(.read)
        #expect(permissions == [.write, .execute])
    }

    @Test("a declared Codable encodes the set as its raw value")
    func codableEncodesTheRawValue() throws {
        let permissions: Permissions = [.read, .execute]
        let data = try JSONEncoder().encode(permissions)

        #expect(String(decoding: data, as: UTF8.self) == "33")
        #expect(try JSONDecoder().decode(Permissions.self, from: data) == permissions)
    }
}
