import Foundation
import os
import OSToolbox

// Expansion checks against a direct `import OSToolbox`. The equivalent checks
// against the re-export chain live in `SwiftStdlibToolboxClient` (one hop) and
// `FoundationToolboxClient` (two hops).

// MARK: - Mutex macro

final class MutexHolder: Sendable {
    @Mutex
    private var name: String!

    @Mutex
    private weak var delegate: AnyObject!

    @Mutex
    private var values: [String?] = []

    init(name: String) {
        self.name = name
    }
}

_ = MutexHolder(name: "test")

// MARK: - OSAllocatedUnfairLock macro

@available(SwiftStdlib 5.7, *)
final class UnfairLockHolder: Sendable {
    @OSAllocatedUnfairLock
    private var name: String!

    @OSAllocatedUnfairLock
    private weak var delegate: AnyObject!

    init(name: String) {
        self.name = name
    }
}

if #available(SwiftStdlib 5.7, *) {
    _ = UnfairLockHolder(name: "test")
}

// MARK: - Loggable & #log macros

extension LogCategory {
    static let startup = LogCategory("startup")

    // Every message `#log(category:)` sends here starts with "[StartupPhase] ".
    static let startupPhase = LogCategory("StartupPhase", prefixesMessages: true)
}

@Loggable
struct DiagnosticsService {
    func run() {
        #log(.debug, "plain message")
        #log(.info, category: .startup, "categorised message")

        // Logged as "[StartupPhase] prefixed message".
        #log(.info, category: .startupPhase, "prefixed message")

        // The expansion binds the category to a closure parameter of this
        // very name, and still takes a caller's variable of that name: the
        // argument is evaluated outside the closure.
        let selectedLogCategory = LogCategory.startupPhase
        #log(.info, category: selectedLogCategory, "category held in a variable")
    }
}

DiagnosticsService().run()

// The no-Foundation guards moved to their own target, `OSToolboxNoFoundationClient`
// — the `import Foundation` at the top of this file was silently satisfying them,
// because Swift resolves conformances module-wide rather than per file.
