// `@FlagSet` compiled for real, in the shapes the expansion tests can only show
// as text: a public set, whose `@inlinable` initializers may name nothing less
// visible; a retired case, whose deprecation goes onto its static without the
// static's own initializer warning about the case; a case gated by
// availability; and a case behind `#if`. Building this target must produce no
// warnings.
import SwiftStdlibToolbox

@FlagSet
public struct RenderingOptions: Hashable, Sendable {
    public enum Flag: Int, Sendable {
        /// Draws the content at the display's native scale.
        case nativeScale = 0
        case antialiasing = 1
        @available(*, deprecated, message: "Subpixel rendering is no longer supported")
        case subpixel = 2
        @available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
        case extendedRange = 3
        #if os(macOS)
        case windowServerComposited = 4
        #endif
    }
}

func describeRenderingOptions() -> String {
    var options: RenderingOptions = [.nativeScale, .antialiasing]
    if #available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *) {
        options.insert(.extendedRange)
    }
    #if os(macOS)
    options.insert(.windowServerComposited)
    #endif
    return "\(options.rawValue) \(RenderingOptions(.antialiasing).rawValue)"
}
