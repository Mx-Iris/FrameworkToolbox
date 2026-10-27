import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import MacroToolbox

public struct MutexMacro: LockMacroProtocol {
    public static let macroName = "Mutex"

    /// The storage type is spelled with its module because the standard
    /// library's `Synchronization` declares a `Mutex` too: in any file that
    /// imports both, a bare `Mutex` is ambiguous, and the error lands on
    /// generated code the caller never wrote.
    public static func makeStorageDecl(for info: LockPropertyInfo) -> DeclSyntax {
        let staticKeyword = info.isStatic ? "static " : ""
        if info.isWeak {
            return """
            private \(raw: staticKeyword)let \(raw: info.storageName) = OSToolbox.Mutex(OSToolbox.WeakBox<\(raw: info.baseType)>(\(info.initialValue)))
            """
        } else if info.isImplicitlyUnwrappedOptional {
            return """
            private \(raw: staticKeyword)let \(raw: info.storageName) = OSToolbox.Mutex<\(raw: info.baseType)?>(\(info.initialValue))
            """
        } else {
            return """
            private \(raw: staticKeyword)let \(raw: info.storageName) = OSToolbox.Mutex<\(raw: info.type)>(\(info.initialValue))
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
        if info.isWeak {
            return """
            set {
                \(raw: info.storageName).withLock { (weakBox: inout OSToolbox.WeakBox<\(raw: info.baseType)>) -> Void in
                    weakBox.value = newValue
                }
            }
            """
        } else {
            let paramType = info.isImplicitlyUnwrappedOptional ? "\(info.baseType)?" : "\(info.type)"
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
