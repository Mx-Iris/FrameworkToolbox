import Testing
import Foundation
@testable import FoundationToolbox

@Suite("#Selector runtime behavior")
struct SelectorMacroRuntimeTests {

    @Test("single-argument selector matches #selector")
    func singleArgumentMatchesBuiltIn() {
        let fromMacro = #Selector("description")
        let fromBuiltIn = #selector(NSObject.description)
        #expect(fromMacro == fromBuiltIn)
    }

    @Test("selector string round-trips through the ObjC runtime")
    func roundTripString() {
        let raw = "viewDidLoad"
        let selector = #Selector("viewDidLoad")
        #expect(NSStringFromSelector(selector) == raw)
    }

    @Test("multi-argument selector round-trips")
    func multiArgumentRoundTrip() {
        let raw = "tableView:didSelectRowAtIndexPath:"
        let selector = #Selector("tableView:didSelectRowAtIndexPath:")
        #expect(NSStringFromSelector(selector) == raw)
    }
}
