#if canImport(ObjectiveC)
import os

/// One `OSLog` for the whole `DynamicInvocation/` path — ``DynamicObject`` and
/// ``RuntimeInvocation`` share the subsystem/category pair on purpose, so a
/// single `log stream` predicate covers everything from member access to
/// return value.
///
/// A hand-written handle rather than `@Loggable`/`#log`, matching
/// `DynamicSubclass.runtimeLog` and `RuntimeMethodHook.hookLog`: this target
/// must not depend on any toolbox layer at runtime, or Xcode builds the
/// `.dynamic` product's transitive closure as shared dynamic frameworks — see
/// the `objc-runtime-toolbox-self-contained-leaf` proposal.
let dynamicInvocationLog = OSLog(subsystem: "ObjCRuntimeToolbox", category: "DynamicInvocation")

#endif
