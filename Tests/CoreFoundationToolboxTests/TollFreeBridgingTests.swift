import CoreFoundation
import XCTest
import CoreFoundationToolbox

final class TollFreeBridgingTests: XCTestCase {

    func testCast() {
        let num = CFNumber.box.from(NSNumber(value: 42))
        XCTAssertNotNil(CFNumber.box.cast(num as Any))
        XCTAssertNil(CFString.box.cast(num as Any))
    }

    func testCastMutable() {
        let str = CFString.box.from(NSString(string: "foo"))
        let mutable = str.box.mutableCopy()
        XCTAssertNotNil(CFString.box.cast(str as Any))
        XCTAssertNotNil(CFString.box.cast(mutable as Any))
        XCTAssertNotNil(CFMutableString.box.cast(mutable as Any))
        // FIXME: cast mutable bridgeable type
        // XCTAssertNil(cfCast(str as Any, to: CFMutableString.self))
    }
}
