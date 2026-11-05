// `@BitField` the way a new app target compiles it. Everything here is
// main-actor isolated unless it says otherwise. The macro adds a getter to a
// property and so cannot change its isolation: a flag word left on the main
// actor is read there, like any computed property of it — reading one from a
// `nonisolated` function is `main actor-isolated property … can not be
// referenced from a nonisolated context` (measured). A flag word taken off the
// main actor is read from a `nonisolated` function, so nothing the expansion
// calls may be main-actor isolated; that holds even while the enumeration it
// reads stays on the main actor, since a raw-value enumeration's conformance to
// `RawRepresentable` is not isolated. A file of its own: `main.swift` compiles
// top-level code under different rules, and a pin placed there would prove
// nothing.
import FoundationToolbox

/// Left on the main actor, as everything is by default here.
enum TransferStage: UInt8 {
    case queued = 0
    case running = 1
    case finished = 2
}

/// Left on the main actor.
struct UploadState: RawRepresentable {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0)
    var isPaused: Bool

    @BitField(bits: 1..<3)
    var stage: TransferStage?
}

/// Taken off the main actor by the caller; the enumeration it reads is not.
nonisolated struct DownloadState: RawRepresentable {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0)
    var isPaused: Bool

    @BitField(bits: 1..<3)
    var stage: TransferStage?
}

func describe(_ uploadState: UploadState) -> String {
    "\(uploadState.isPaused) \(String(describing: uploadState.stage))"
}

nonisolated func describe(_ downloadState: DownloadState) -> String {
    "\(downloadState.isPaused) \(String(describing: downloadState.stage))"
}
