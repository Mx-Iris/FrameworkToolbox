import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import MacroToolbox

public struct OSAllocatedUnfairLockMacro: LockMacroProtocol {
    public static let macroName = "OSAllocatedUnfairLock"

    public static func makeStorageDecl(for info: LockPropertyInfo) -> DeclSyntax {
        if info.isWeak {
            return """
            private let \(raw: info.storageName) = OSAllocatedUnfairLock(initialState: SwiftStdlibToolbox.WeakBox<\(raw: info.baseType)>(\(info.initialValue)))
            """
        } else if info.isImplicitlyUnwrappedOptional {
            return """
            private let \(raw: info.storageName) = OSAllocatedUnfairLock<\(raw: info.baseType)?>(initialState: \(info.initialValue))
            """
        } else {
            return """
            private let \(raw: info.storageName) = OSAllocatedUnfairLock<\(raw: info.type)>(initialState: \(info.initialValue))
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
                \(raw: info.storageName).withLock { (weakBox: inout SwiftStdlibToolbox.WeakBox<\(raw: info.baseType)>) -> Void in
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
}
