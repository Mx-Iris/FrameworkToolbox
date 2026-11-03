import Testing
import os

@testable import OSToolbox

// `@Loggable` and `@Signpostable` copy their `subsystem:` and `category:`
// arguments into the generated getters as written, so anything that evaluates
// to a `String` names them — above all a constant declared once in the module,
// which is how a module keeps every type under one subsystem without repeating
// the string. These run the real expansion through the compiler; the snapshots
// in `OSToolboxMacroTests` only show its text.

let nameArgumentSubsystem = "com.example.name-arguments"

enum NameArgumentCategories {
    static let persistence = "Persistence"
}

@Loggable(.internal, subsystem: nameArgumentSubsystem, category: NameArgumentCategories.persistence)
@Signpostable(.internal, subsystem: nameArgumentSubsystem, category: NameArgumentCategories.persistence)
private struct ConstantNamedStore {}

@Loggable(.internal, subsystem: nil, category: nil)
@Signpostable(.internal, subsystem: nil, category: nil)
private struct ExplicitlyUnnamedStore {}

@Suite
struct NameArgumentTests {

    @Test func loggableReadsModuleConstants() {
        #expect(ConstantNamedStore.subsystem == nameArgumentSubsystem)
        #expect(ConstantNamedStore.category == NameArgumentCategories.persistence)
    }

    @Test func signpostableReadsModuleConstants() {
        #expect(ConstantNamedStore.signpostSubsystem == nameArgumentSubsystem)
        #expect(ConstantNamedStore.signpostCategory == NameArgumentCategories.persistence)
    }

    /// `nil` is what both parameters default to, so writing it out has to mean
    /// the same thing: the type's own name.
    @Test func explicitNilFallsBackToTheTypeName() {
        #expect(ExplicitlyUnnamedStore.subsystem == "ExplicitlyUnnamedStore")
        #expect(ExplicitlyUnnamedStore.category == "ExplicitlyUnnamedStore")
        #expect(ExplicitlyUnnamedStore.signpostSubsystem == "ExplicitlyUnnamedStore")
        #expect(ExplicitlyUnnamedStore.signpostCategory == "ExplicitlyUnnamedStore")
    }
}
