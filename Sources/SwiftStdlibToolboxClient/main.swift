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

let uint = 8.bitPattern.uint
_ = ClassDecl(property: "")




protocol TestProtocol {}
import FrameworkToolbox

@FrameworkToolboxExtension(.internal)
extension TestProtocol {}


@AssociatedValue(.public)
enum EnumAssociatedValue {
    case optional(String?)
}

// MARK: - Loggable & #log macro verification

import FoundationToolbox

@Loggable
struct LoggableStruct {
    func doWork() {
        let value = 42
        #log(.debug, "Processing value: \(value, privacy: .public)")
    }
}

@Loggable
class LoggableClass {
    func handle() {
        #log(.info, "Handling request")
    }
}
