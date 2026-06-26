# Available Storage Macros Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `@AvailableNonMutating` and `@AvailableMutating` property macros that generate `Any?` backing storage for `@available`-gated properties.

**Architecture:** Implement two attached `PeerMacro` + `AccessorMacro` types in `SwiftStdlibToolboxMacros` that share one parser and expansion helper. The peer expansion emits `<propertyName>Storage: Any?`; the accessor expansion emits a lazy getter for both macros and a setter only for `@AvailableMutating`.

**Tech Stack:** Swift 6.3, SwiftSyntax, SwiftSyntaxMacros, MacroTesting, SwiftPM package traits.

---

### Task 1: Add Failing Macro Expansion Tests

**Files:**
- Create: `Tests/SwiftStdlibToolboxMacroTests/AvailableMacroTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiftStdlibToolboxMacroTests/AvailableMacroTests.swift`:

```swift
import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "AvailableNonMutating": AvailableNonMutatingMacro.self,
    "AvailableMutating": AvailableMutatingMacro.self,
]))
struct AvailableMacroTests {

    @Test func nonMutatingProperty() {
        assertMacro {
            """
            @AvailableNonMutating(WindowController())
            @available(macOS 15, *)
            private var windowController: WindowController
            """
        } expansion: {
            """
            @available(macOS 15, *)
            private var windowController: WindowController {
                get {
                    if let existingValue = windowControllerStorage as? WindowController {
                        return existingValue
                    }
                    let defaultValue = WindowController()
                    windowControllerStorage = defaultValue
                    return defaultValue
                }
            }

            private var windowControllerStorage: Any?
            """
        }
    }

    @Test func mutatingProperty() {
        assertMacro {
            """
            @AvailableMutating(WindowController())
            @available(macOS 15, *)
            private var windowController: WindowController
            """
        } expansion: {
            """
            @available(macOS 15, *)
            private var windowController: WindowController {
                get {
                    if let existingValue = windowControllerStorage as? WindowController {
                        return existingValue
                    }
                    let defaultValue = WindowController()
                    windowControllerStorage = defaultValue
                    return defaultValue
                }
                set {
                    windowControllerStorage = newValue
                }
            }

            private var windowControllerStorage: Any?
            """
        }
    }

    @Test func staticMutatingProperty() {
        assertMacro {
            """
            @AvailableMutating(WindowController())
            @available(macOS 15, *)
            private static var windowController: WindowController
            """
        } expansion: {
            """
            @available(macOS 15, *)
            private static var windowController: WindowController {
                get {
                    if let existingValue = windowControllerStorage as? WindowController {
                        return existingValue
                    }
                    let defaultValue = WindowController()
                    windowControllerStorage = defaultValue
                    return defaultValue
                }
                set {
                    windowControllerStorage = newValue
                }
            }

            private static var windowControllerStorage: Any?
            """
        }
    }

    @Test func missingDefaultValue() {
        assertMacro {
            """
            @AvailableMutating
            private var windowController: WindowController
            """
        } diagnostics: {
            """
            @AvailableMutating
            ┬─────────────────
            ╰─ 🛑 @AvailableMutating requires exactly one default value argument.
            private var windowController: WindowController
            """
        }
    }

    @Test func missingExplicitType() {
        assertMacro {
            """
            @AvailableNonMutating(WindowController())
            private var windowController
            """
        } diagnostics: {
            """
            @AvailableNonMutating(WindowController())
            ┬────────────────────────────────────────
            ╰─ 🛑 @AvailableNonMutating requires an explicit type annotation.
            private var windowController
            """
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter AvailableMacroTests 2>&1 | xcsift
```

Expected: fails because `AvailableNonMutatingMacro` and `AvailableMutatingMacro` are not defined.

### Task 2: Add Public Macro Declarations

**Files:**
- Create: `Sources/SwiftStdlibToolbox/Macros/AvailableMacro.swift`

- [ ] **Step 1: Add public macro declarations**

Create `Sources/SwiftStdlibToolbox/Macros/AvailableMacro.swift`:

```swift
/// A property macro that creates `Any?` storage and a lazy getter for
/// availability-gated properties whose backing storage cannot mention the
/// gated type directly.
@attached(peer, names: suffixed(Storage))
@attached(accessor)
public macro AvailableNonMutating(_ defaultValue: Any) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AvailableNonMutatingMacro"
)

/// A property macro that creates `Any?` storage, a lazy getter, and a setter for
/// availability-gated properties whose backing storage cannot mention the
/// gated type directly.
@attached(peer, names: suffixed(Storage))
@attached(accessor)
public macro AvailableMutating(_ defaultValue: Any) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AvailableMutatingMacro"
)
```

- [ ] **Step 2: Run tests to keep failure focused**

Run:

```bash
swift test --filter AvailableMacroTests 2>&1 | xcsift
```

Expected: still fails because the macro implementation types are not defined.

### Task 3: Implement Shared Macro Logic

**Files:**
- Create: `Sources/SwiftStdlibToolboxMacros/AvailableMacro.swift`
- Modify: `Sources/SwiftStdlibToolboxMacros/MainPlugin.swift`

- [ ] **Step 1: Add macro implementation**

Create `Sources/SwiftStdlibToolboxMacros/AvailableMacro.swift`:

```swift
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct AvailableNonMutatingMacro: AvailableStorageMacroProtocol {
    static let macroName = "AvailableNonMutating"
    static let emitsSetter = false
}

public struct AvailableMutatingMacro: AvailableStorageMacroProtocol {
    static let macroName = "AvailableMutating"
    static let emitsSetter = true
}

protocol AvailableStorageMacroProtocol: PeerMacro, AccessorMacro {
    static var macroName: String { get }
    static var emitsSetter: Bool { get }
}

extension AvailableStorageMacroProtocol {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let propertyInfo = try AvailableStoragePropertyParser.parse(
            declaration,
            attribute: node,
            macroName: macroName
        )
        let staticKeyword = propertyInfo.isStatic ? "static " : ""
        return [
            """
            private \(raw: staticKeyword)var \(raw: propertyInfo.storageName): Any?
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let propertyInfo = try AvailableStoragePropertyParser.parse(
            declaration,
            attribute: node,
            macroName: macroName
        )

        var accessors: [AccessorDeclSyntax] = [
            """
            get {
                if let existingValue = \(raw: propertyInfo.storageName) as? \(propertyInfo.type) {
                    return existingValue
                }
                let defaultValue = \(propertyInfo.defaultValue)
                \(raw: propertyInfo.storageName) = defaultValue
                return defaultValue
            }
            """
        ]

        if emitsSetter {
            accessors.append(
                """
                set {
                    \(raw: propertyInfo.storageName) = newValue
                }
                """
            )
        }

        return accessors
    }
}

struct AvailableStoragePropertyInfo {
    let propertyName: String
    let storageName: String
    let type: TypeSyntax
    let defaultValue: ExprSyntax
    let isStatic: Bool
}

enum AvailableStoragePropertyParser {
    static func parse(
        _ declaration: some DeclSyntaxProtocol,
        attribute: AttributeSyntax,
        macroName: String
    ) throws -> AvailableStoragePropertyInfo {
        guard let variableDeclaration = declaration.as(VariableDeclSyntax.self),
              variableDeclaration.bindingSpecifier.tokenKind == .keyword(.var) else {
            throw AvailableStorageMacroError.requiresVariable(macroName)
        }

        guard variableDeclaration.bindings.count == 1,
              let propertyBinding = variableDeclaration.bindings.first,
              let identifierPattern = propertyBinding.pattern.as(IdentifierPatternSyntax.self) else {
            throw AvailableStorageMacroError.invalidPropertyBinding(macroName)
        }

        if propertyBinding.accessorBlock != nil {
            throw AvailableStorageMacroError.cannotHaveExistingAccessors(macroName)
        }

        guard let type = propertyBinding.typeAnnotation?.type else {
            throw AvailableStorageMacroError.requiresExplicitType(macroName)
        }

        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
              arguments.count == 1,
              let defaultValue = arguments.first?.expression else {
            throw AvailableStorageMacroError.requiresDefaultValue(macroName)
        }

        let isStatic = variableDeclaration.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
        }
        let propertyName = identifierPattern.identifier.text

        return AvailableStoragePropertyInfo(
            propertyName: propertyName,
            storageName: "\(propertyName)Storage",
            type: type,
            defaultValue: defaultValue,
            isStatic: isStatic
        )
    }
}

enum AvailableStorageMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresVariable(String)
    case invalidPropertyBinding(String)
    case cannotHaveExistingAccessors(String)
    case requiresExplicitType(String)
    case requiresDefaultValue(String)

    var description: String {
        switch self {
        case .requiresVariable(let macroName):
            return "@\(macroName) can only be applied to a variable declaration."
        case .invalidPropertyBinding(let macroName):
            return "@\(macroName) requires a single named property binding."
        case .cannotHaveExistingAccessors(let macroName):
            return "@\(macroName) cannot be applied to computed properties or properties with existing accessors."
        case .requiresExplicitType(let macroName):
            return "@\(macroName) requires an explicit type annotation."
        case .requiresDefaultValue(let macroName):
            return "@\(macroName) requires exactly one default value argument."
        }
    }

    var message: String { description }

    var diagnosticID: MessageID {
        let diagnosticName: String
        switch self {
        case .requiresVariable:
            diagnosticName = "requiresVariable"
        case .invalidPropertyBinding:
            diagnosticName = "invalidPropertyBinding"
        case .cannotHaveExistingAccessors:
            diagnosticName = "cannotHaveExistingAccessors"
        case .requiresExplicitType:
            diagnosticName = "requiresExplicitType"
        case .requiresDefaultValue:
            diagnosticName = "requiresDefaultValue"
        }
        return MessageID(domain: "AvailableStorageMacroError", id: diagnosticName)
    }

    var severity: DiagnosticSeverity { .error }
}
```

- [ ] **Step 2: Register macro types in the plugin**

Modify `Sources/SwiftStdlibToolboxMacros/MainPlugin.swift` so `providingMacros` includes the two macro types:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MutexMacro.self,
        EquatableMacro.self,
        EquatableIgnoredMacro.self,
        EquatableIgnoredUnsafeClosureMacro.self,
        AssociatedValueMacro.self,
        CaseCheckableMacro.self,
        AvailableNonMutatingMacro.self,
        AvailableMutatingMacro.self,
    ]
}
```

- [ ] **Step 3: Run tests to verify macro tests pass**

Run:

```bash
swift test --filter AvailableMacroTests 2>&1 | xcsift
```

Expected: all `AvailableMacroTests` pass.

### Task 4: Update Project Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Document the new macro pattern**

Modify the `SwiftStdlibToolbox` row in `CLAUDE.md` to include the new macros:

```markdown
| `SwiftStdlibToolbox` | Swift stdlib extensions + macros (`@Equatable`, `@AssociatedValue`, `@CaseCheckable`, `@Mutex`, `@AvailableNonMutating`, `@AvailableMutating`) |
```

Add a Key Patterns bullet:

```markdown
- **Available storage macros:** `@AvailableNonMutating` and `@AvailableMutating` generate `Any?` backing storage plus lazy accessors for `@available`-gated properties whose storage cannot mention the gated type directly. The mutating variant also emits a setter.
```

- [ ] **Step 2: Run broader SwiftStdlib macro tests**

Run:

```bash
swift test --filter SwiftStdlibToolboxMacroTests 2>&1 | xcsift
```

Expected: all SwiftStdlib macro tests pass.

### Task 5: Final Verification and Commit

**Files:**
- Verify: `Sources/SwiftStdlibToolbox/Macros/AvailableMacro.swift`
- Verify: `Sources/SwiftStdlibToolboxMacros/AvailableMacro.swift`
- Verify: `Sources/SwiftStdlibToolboxMacros/MainPlugin.swift`
- Verify: `Tests/SwiftStdlibToolboxMacroTests/AvailableMacroTests.swift`
- Verify: `CLAUDE.md`

- [ ] **Step 1: Run package update**

Run:

```bash
swift package update 2>&1 | xcsift
```

Expected: status success with zero errors.

- [ ] **Step 2: Run final focused tests**

Run:

```bash
swift test --filter AvailableMacroTests 2>&1 | xcsift
swift test --filter SwiftStdlibToolboxMacroTests 2>&1 | xcsift
```

Expected: both commands report success with zero errors and zero failed tests.

- [ ] **Step 3: Inspect the diff**

Run:

```bash
git diff --stat
git diff -- Sources/SwiftStdlibToolbox/Macros/AvailableMacro.swift Sources/SwiftStdlibToolboxMacros/AvailableMacro.swift Sources/SwiftStdlibToolboxMacros/MainPlugin.swift Tests/SwiftStdlibToolboxMacroTests/AvailableMacroTests.swift CLAUDE.md
```

Expected: diff only contains the new available storage macros, tests, plugin registration, and documentation.

- [ ] **Step 4: Commit the implementation**

Run:

```bash
git add Sources/SwiftStdlibToolbox/Macros/AvailableMacro.swift Sources/SwiftStdlibToolboxMacros/AvailableMacro.swift Sources/SwiftStdlibToolboxMacros/MainPlugin.swift Tests/SwiftStdlibToolboxMacroTests/AvailableMacroTests.swift CLAUDE.md docs/superpowers/plans/2026-04-14-available-storage-macros.md
git commit -m "feat: add available storage macros"
```

Expected: commit succeeds.
