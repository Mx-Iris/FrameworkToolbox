import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import MacroToolbox

public struct OSAllocatedUnfairLockMacro: LockMacroProtocol {
    public static let macroName = "OSAllocatedUnfairLock"

    public static func makeStorageDecl(for info: LockPropertyInfo) -> DeclSyntax {
        let staticKeyword = info.isStatic ? "static " : ""
        // Weak and implicitly unwrapped properties always carry a type: the
        // parser rejects the first without one, and the second is a type.
        guard let type = info.type, let baseType = info.baseType else {
            return """
            private \(raw: staticKeyword)let \(raw: info.storageName) = os.OSAllocatedUnfairLock(initialState: \(info.initialValue))
            """
        }
        if info.isWeak {
            return """
            private \(raw: staticKeyword)let \(raw: info.storageName) = os.OSAllocatedUnfairLock(initialState: OSToolbox.WeakBox<\(raw: baseType)>(\(info.initialValue)))
            """
        } else if info.isImplicitlyUnwrappedOptional {
            return """
            private \(raw: staticKeyword)let \(raw: info.storageName) = os.OSAllocatedUnfairLock<\(raw: baseType)?>(initialState: \(info.initialValue))
            """
        } else {
            return """
            private \(raw: staticKeyword)let \(raw: info.storageName) = os.OSAllocatedUnfairLock<\(raw: type)>(initialState: \(info.initialValue))
            """
        }
    }

    public static func makeGetter(for info: LockPropertyInfo) -> AccessorDeclSyntax {
        if info.isWeak {
            return """
            get {
                \(raw: info.storageName).withLock { $0.value }
            }
            """
        } else if info.isImplicitlyUnwrappedOptional {
            return """
            get {
                \(raw: info.storageName).withLock { $0! }
            }
            """
        } else {
            return """
            get {
                \(raw: info.storageName).withLock { $0 }
            }
            """
        }
    }

    public static func makeSetter(for info: LockPropertyInfo) -> AccessorDeclSyntax {
        guard let type = info.type, let baseType = info.baseType else {
            return """
            set {
                \(raw: info.storageName).withLock { $0 = newValue }
            }
            """
        }
        if info.isWeak {
            return """
            set {
                \(raw: info.storageName).withLock { (weakBox: inout OSToolbox.WeakBox<\(raw: baseType)>) -> Void in
                    weakBox.value = newValue
                }
            }
            """
        } else {
            let paramType = info.isImplicitlyUnwrappedOptional ? "\(baseType)?" : "\(type)"
            return """
            set {
                \(raw: info.storageName).withLock { (value: inout \(raw: paramType)) -> Void in
                    value = newValue
                }
            }
            """
        }
    }

    public static func makeModify(for info: LockPropertyInfo) -> AccessorDeclSyntax? {
        if info.isWeak || info.isImplicitlyUnwrappedOptional {
            return nil
        }
        return """
        _modify {
            let valuePointer = \(raw: info.storageName)._unsafeLock()
            defer { \(raw: info.storageName)._unsafeUnlock() }
            yield &valuePointer.pointee
        }
        """
    }
}
