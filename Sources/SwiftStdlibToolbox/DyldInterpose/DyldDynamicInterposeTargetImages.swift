#if canImport(Darwin) && _pointerBitWidth(_64)

/// Which loaded images ``DyldDynamicInterpose`` should rewrite.
///
/// dyld's own `dyld_dynamic_interpose` only ever took a single `mach_header`.
/// Widening that to "every image" is what makes the replacement observable
/// from code you did not write, so the selector is explicit rather than
/// implied.
public struct DyldDynamicInterposeTargetImages: Sendable {
    enum Selection: @unchecked Sendable {
        case allImages
        case mainExecutable
        case singleImage(UnsafeRawPointer)
        case pathPredicate(@Sendable (String) -> Bool)
    }

    let selection: Selection

    /// Every image mapped into the process.
    public static let allImages = Self(selection: .allImages)

    /// Only the `MH_EXECUTE` image — the program itself.
    public static let mainExecutable = Self(selection: .mainExecutable)

    /// A single image, identified by its Mach-O header. `#dsohandle` yields
    /// the header of the image containing the call site.
    public static func image(_ machHeader: UnsafeRawPointer) -> Self {
        Self(selection: .singleImage(machHeader))
    }

    /// Every image whose filesystem path satisfies `predicate`.
    public static func imagesWithPath(
        matching predicate: @escaping @Sendable (String) -> Bool
    ) -> Self {
        Self(selection: .pathPredicate(predicate))
    }

    func matches(_ image: LoadedMachOImage) -> Bool {
        switch selection {
        case .allImages:
            return true
        case .mainExecutable:
            return image.isMainExecutable
        case .singleImage(let machHeader):
            return UnsafeRawPointer(image.machHeader) == machHeader
        case .pathPredicate(let predicate):
            return predicate(image.path)
        }
    }
}

#endif
