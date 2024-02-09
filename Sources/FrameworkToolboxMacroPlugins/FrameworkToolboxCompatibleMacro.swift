import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public enum FrameworkToolboxCompatibleMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        return [
            """
            @inlinable
            public static var box: FrameworkToolbox<Self>.Type {
                set {}
                get { FrameworkToolbox<Self>.self }
            }
            """,
            """
            @inlinable
            public var box: FrameworkToolbox<Self> {
                set {}
                get { FrameworkToolbox(self) }
            }
            """,
            """
            public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            public subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            public subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                box[keyPath: keyPath]
            }
            """,
            """
            public static subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            public static subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                set { box[keyPath: keyPath] = newValue }
                get { box[keyPath: keyPath] }
            }
            """,
            """
            public static subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                box[keyPath: keyPath]
            }
            """,
        ]
    }
}
