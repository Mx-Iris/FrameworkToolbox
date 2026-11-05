// `@FlagSet` the way a new app target compiles it. Everything here is main-actor
// isolated unless it says otherwise, generated code included, and both sets are
// used from a `nonisolated` function — so the conformance, the initializers and
// the statics the macro generates all have to be usable off the main actor.
// A file of its own: `main.swift` compiles top-level code under different rules,
// and a pin placed there would prove nothing.
import FoundationToolbox

/// Left on the main actor, as everything is by default here.
@FlagSet
struct UploadOptions {
    enum Flag: Int {
        case resumable = 0
        case background = 1
    }
}

/// Taken off the main actor by the caller.
@FlagSet
nonisolated struct DownloadOptions {
    enum Flag: Int {
        case cellular = 0
    }
}

nonisolated func describe(_ uploadOptions: UploadOptions, _ downloadOptions: DownloadOptions) -> String {
    var options = uploadOptions
    options.insert(.background)
    let resumable = UploadOptions(.resumable)
    return "\(options.contains(.resumable)) \(options.rawValue) \(resumable.rawValue) "
        + "\(downloadOptions.contains(.cellular)) \(DownloadOptions(.cellular).rawValue)"
}
