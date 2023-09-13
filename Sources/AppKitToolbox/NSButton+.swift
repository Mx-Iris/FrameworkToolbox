#if canImport(AppKit)

import AppKit
import FrameworkToolbox

public extension FrameworkToolbox where Base: NSButton {
    func setTarget(_ target: AnyObject, action: Selector) {
        base.target = target
        base.action = action
    }
}

public extension NSButton {
    convenience init(
        title: String = "",
        titleColor: NSColor = .labelColor,
        titleFont: NSFont = .systemFont(ofSize: 14),
        alternateTitle: String = "",
        alternateTitleColor: NSColor = .labelColor,
        alternateTitleFont: NSFont = .systemFont(ofSize: 14),
        image: NSImage? = nil,
        alternateImage: NSImage? = nil,
        buttonType: NSButton.ButtonType = .momentaryLight,
        bezelStyle: NSButton.BezelStyle = .rounded
    ) {
        self.init(frame: .zero)
        self.attributedTitle = NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: titleColor])
        self.attributedAlternateTitle = NSAttributedString(string: alternateTitle, attributes: [.font: alternateTitleFont, .foregroundColor: alternateTitleColor])
        self.image = image
        self.alternateImage = alternateImage
        setButtonType(buttonType)
        self.bezelStyle = bezelStyle
    }
}

#endif
