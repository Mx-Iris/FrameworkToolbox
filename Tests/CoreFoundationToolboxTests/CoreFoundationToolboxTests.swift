import CoreFoundation
import XCTest
import CoreFoundationToolbox

final class CoreFoundationToolboxTests: XCTestCase {

    func testBridgeContainer() {
        let key = CFError.UserInfoKey.description
        let cfdict = [key: 42]._bridgeToCF()
        let bridged = cfdict.box.value(key: key.rawValue)!
        XCTAssertNotNil(CFNumber.box.cast(bridged))
    }

    func testBridgeNestedContainer() throws {
        let key = CFError.UserInfoKey.description
        let cfarray = [[key: 42]]._bridgeToCF()
        let cfdict = CFDictionary.box.cast(cfarray.box.value(at: 0))!
        let bridged = cfdict.box.value(key: key.rawValue)!
        XCTAssertNotNil(CFNumber.box.cast(bridged))
    }

    func testCFArrayCallBacks() {
        let arr = CFMutableArray.box.create()
        weak var weakObj: AnyObject?
        do {
            let data = CFData.box.create(bytes: nil, length: 0)
            arr.box.append(data)
            weakObj = data
        }
        XCTAssertNotNil(weakObj)
    }
}
