// `#log(category:)` evaluates its category expression as the argument of the
// closure it expands to, in the isolation of the call site, and the message
// prefix is read from that same value inside the closure.
//
// In a module like this one, a category declared as a plain `static let` is
// main-actor isolated, so logging to it from a `nonisolated` function fails
// with "main actor-isolated static property 'mirroring' can not be referenced
// from a nonisolated context", reported against the `#log` expansion
// (measured by dropping the keyword below). The expansion from before the
// message prefix reached the category in the same place, so this is not new —
// but the error points at generated code, hence the pin. `LogCategory` is
// `Sendable`, so `nonisolated` is safe.
import FoundationToolbox

extension LogCategory {
    nonisolated static let mirroring = LogCategory("Mirroring", prefixesMessages: true)
}

@Loggable
struct MirroringService {
    nonisolated func mirror() {
        #log(.info, category: .mirroring, "mirroring")
    }
}

nonisolated func mirrorInBackground(_ service: MirroringService) {
    service.mirror()
}
