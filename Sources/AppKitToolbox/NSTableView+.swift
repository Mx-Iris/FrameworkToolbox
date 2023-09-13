#if canImport(AppKit)

import AppKit
import FrameworkToolbox

public extension FrameworkToolbox where Base: NSTableView {
    func makeView<CellView: NSTableCellView>(withType: CellView.Type, onwer: Any?) -> CellView {
        if let reuseView = base.makeView(withIdentifier: CellView.box.typeNameIdentifier, owner: onwer) as? CellView {
            return reuseView
        } else {
            let cellView = CellView()
            cellView.identifier = CellView.box.typeNameIdentifier
            return CellView()
        }
    }
}






#endif
