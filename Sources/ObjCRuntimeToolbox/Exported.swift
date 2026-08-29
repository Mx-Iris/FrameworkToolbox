// Every macro in this target expands to `NSSelectorFromString(_:)` —
// `@RuntimeClassProxy`, `@RuntimeClassHook`, `@RuntimeMethodReplacement`, and
// `@DynamicSubclassHook` by way of the generated override bodies. That function
// is Foundation, not ObjectiveC, so without this line a caller who writes only
// `import ObjCRuntimeToolbox` gets `cannot find 'NSSelectorFromString' in scope`
// pointing at generated code their source never mentions.
//
// This is the same defect class as `#log`'s hidden Foundation dependency (see
// the rule in `CLAUDE.md`), and re-exporting is the right fix rather than
// rewriting the expansions: this target is Objective-C interop, and every
// realistic caller of an isa-swizzling or runtime-proxy macro is holding
// `NSObject` subclasses already. `Sources/ObjCRuntimeToolboxSoleImportClient/`
// pins it.
#if canImport(Foundation)
@_exported import Foundation
#endif

#if canImport(ObjectiveC)
@_exported import ObjectiveC
#endif
