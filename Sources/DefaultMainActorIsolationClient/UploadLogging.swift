// `@Loggable` and `@Signpostable` copy their `subsystem:` and `category:`
// arguments into `nonisolated` getters. In a module whose default isolation is
// the main actor, a global `let` in an ordinary source file is main-actor
// isolated like everything else, so reading it from those getters is an error
// in the Swift 6 language mode and a warning in Swift 5 — once per annotated
// type. Constants that name a subsystem or category therefore have to be
// `nonisolated`, which is safe for a `String`.
//
// This has to be a file of its own: in `main.swift` the same plain `let`
// compiles clean in both language modes (measured), which is how the first
// version of this check passed while proving nothing.
nonisolated let uploadSubsystem = "com.example.upload"
nonisolated let uploadCategory = "Upload"
