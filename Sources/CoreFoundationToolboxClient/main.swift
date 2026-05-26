import CoreFoundation
import Foundation
import CoreFoundationToolbox

// MARK: - Box namespace: cast

let anyString: Any = "hello" as CFString
if let castString = CFString.box.cast(anyString) {
    print("cast succeeded, length=\(castString.box.length)")
}

// MARK: - Toll-free bridging via box namespace

let cfString: CFString = CFString.box.from("world")
let nsString: NSString = cfString.box.asNS()
let swiftString: String = cfString.box.asSwift()
print("bridged: \(nsString) / \(swiftString)")

// MARK: - CFArray via box namespace

let mutableArray = CFMutableArray.box.create()
mutableArray.box.append(CFNumber.box.from(NSNumber(value: 1)))
mutableArray.box.append(CFNumber.box.from(NSNumber(value: 2)))
let immutableArray: CFArray = mutableArray
for value in immutableArray {
    print("array entry: \(value)")
}

// MARK: - CFError via box namespace

let error = CFError.box.create(domain: .posix, code: 42)
print("error domain=\(error.box.domain.rawValue) code=\(error.box.code)")
