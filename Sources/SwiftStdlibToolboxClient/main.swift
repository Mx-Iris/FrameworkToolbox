import Foundation
import SwiftStdlibToolbox

@Equatable
class A {
    let a: String
    let b: Int
    @EquatableIgnored let c: Double
    init(a: String, b: Int, c: Double) {
        self.a = a
        self.b = b
        self.c = c
    }
}


final class ClassDecl: Sendable {
    @Mutex
    private var property: String!
    
    @Mutex
    private weak var delegate: AnyObject!

    @Mutex
    private var array: [String?] = []
    
    init(property: String) {
        self.property = property
        array[safe: 2] = nil
    }
}


_ = ClassDecl(property: "")
