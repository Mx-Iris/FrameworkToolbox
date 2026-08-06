#if canImport(Darwin) && _pointerBitWidth(_64)

import Darwin
import MachO

/// A Mach-O image currently mapped into this process.
struct LoadedMachOImage {
    let machHeader: UnsafePointer<mach_header_64>
    let vmAddressSlide: Int
    let path: String

    var isMainExecutable: Bool {
        machHeader.pointee.filetype == UInt32(MH_EXECUTE)
    }
}

/// One `S_NON_LAZY_SYMBOL_POINTERS` / `S_LAZY_SYMBOL_POINTERS` section, already
/// slid into its runtime location. These are the slots a call to an imported
/// function goes through, and the only thing dynamic interposing rewrites.
struct SymbolPointerSection {
    let segmentName: String
    let sectionName: String
    let firstSlot: UnsafeMutablePointer<UInt>
    let slotCount: Int

    /// Protection to restore once the section has been made writable.
    ///
    /// dyld maps `__DATA_CONST` and `__AUTH_CONST` writable, applies fixups,
    /// then re-protects them read-only — which it records with the segment's
    /// `SG_READ_ONLY` flag. Reproducing that decision here restores exactly the
    /// protection the segment had before we touched it, without needing the
    /// `mach_vm_region` family (unavailable outside macOS).
    let protectionToRestore: Int32
}

enum MachOImageScanner {
    /// `SG_READ_ONLY` from `<mach-o/loader.h>`: dyld re-protects the segment as
    /// read-only once it has applied fixups. Spelled out here because the
    /// macro is not reliably imported into Swift across SDK versions.
    private static let segmentFlagReadOnlyAfterFixups: UInt32 = 0x10

    // MARK: - Image enumeration

    static func loadedImages() -> [LoadedMachOImage] {
        let imageCount = _dyld_image_count()
        var images: [LoadedMachOImage] = []
        images.reserveCapacity(Int(imageCount))

        for imageIndex in 0 ..< imageCount {
            guard let headerPointer = _dyld_get_image_header(imageIndex) else { continue }
            let machHeader = UnsafeRawPointer(headerPointer).assumingMemoryBound(to: mach_header_64.self)
            guard machHeader.pointee.magic == MH_MAGIC_64 else { continue }

            let path = _dyld_get_image_name(imageIndex).map { String(cString: $0) } ?? ""
            images.append(
                LoadedMachOImage(
                    machHeader: machHeader,
                    vmAddressSlide: _dyld_get_image_vmaddr_slide(imageIndex),
                    path: path
                )
            )
        }
        return images
    }

    static func loadedImage(withMachHeader machHeader: UnsafeRawPointer) -> LoadedMachOImage? {
        loadedImages().first { UnsafeRawPointer($0.machHeader) == machHeader }
    }

    // MARK: - Section enumeration

    static func symbolPointerSections(of image: LoadedMachOImage) -> [SymbolPointerSection] {
        var sections: [SymbolPointerSection] = []
        var commandPointer = UnsafeRawPointer(image.machHeader)
            .advanced(by: MemoryLayout<mach_header_64>.size)

        for _ in 0 ..< image.machHeader.pointee.ncmds {
            let command = commandPointer.assumingMemoryBound(to: load_command.self).pointee
            guard command.cmdsize > 0 else { break }

            if command.cmd == UInt32(LC_SEGMENT_64) {
                let segment = commandPointer.assumingMemoryBound(to: segment_command_64.self)
                let segmentName = nullPaddedName(of: segment.pointee.segname)
                let segmentIsReadOnlyAfterFixups =
                    (segment.pointee.flags & segmentFlagReadOnlyAfterFixups) != 0
                let protectionToRestore: Int32 = segmentIsReadOnlyAfterFixups
                    ? PROT_READ
                    : segment.pointee.initprot & (PROT_READ | PROT_WRITE | PROT_EXEC)

                var sectionPointer = UnsafeRawPointer(segment)
                    .advanced(by: MemoryLayout<segment_command_64>.size)

                for _ in 0 ..< segment.pointee.nsects {
                    let section = sectionPointer.assumingMemoryBound(to: section_64.self)
                    let sectionType = section.pointee.flags & UInt32(SECTION_TYPE)
                    let isSymbolPointerSection =
                        sectionType == UInt32(S_NON_LAZY_SYMBOL_POINTERS)
                            || sectionType == UInt32(S_LAZY_SYMBOL_POINTERS)

                    if isSymbolPointerSection, section.pointee.size >= UInt64(MemoryLayout<UInt>.size) {
                        let slotAddress = UInt(section.pointee.addr) &+ UInt(bitPattern: image.vmAddressSlide)
                        if let firstSlot = UnsafeMutableRawPointer(bitPattern: slotAddress) {
                            sections.append(
                                SymbolPointerSection(
                                    segmentName: segmentName,
                                    sectionName: nullPaddedName(of: section.pointee.sectname),
                                    firstSlot: firstSlot.assumingMemoryBound(to: UInt.self),
                                    slotCount: Int(section.pointee.size) / MemoryLayout<UInt>.size,
                                    protectionToRestore: protectionToRestore
                                )
                            )
                        }
                    }
                    sectionPointer = sectionPointer.advanced(by: MemoryLayout<section_64>.size)
                }
            }
            commandPointer = commandPointer.advanced(by: Int(command.cmdsize))
        }
        return sections
    }

    // MARK: - Memory protection

    /// Makes the page range covering `startAddress ..< endAddress` writable,
    /// runs `body`, then restores `protectionToRestore`.
    ///
    /// Returns `nil` on success, or the `errno` value that made the range
    /// impossible to open for writing.
    static func withWritableMemory(
        startAddress: UInt,
        endAddress: UInt,
        restoringProtection protectionToRestore: Int32,
        _ body: () -> Void
    ) -> Int32? {
        let pageSize = UInt(sysconf(_SC_PAGESIZE))
        guard pageSize > 0 else { return EINVAL }

        let alignedStartAddress = startAddress & ~(pageSize &- 1)
        let alignedEndAddress = (endAddress &+ pageSize &- 1) & ~(pageSize &- 1)
        guard alignedEndAddress > alignedStartAddress,
              let regionStart = UnsafeMutableRawPointer(bitPattern: alignedStartAddress)
        else {
            return EINVAL
        }
        let regionLength = Int(alignedEndAddress - alignedStartAddress)

        guard mprotect(regionStart, regionLength, PROT_READ | PROT_WRITE) == 0 else {
            return errno
        }
        body()
        mprotect(regionStart, regionLength, protectionToRestore)
        return nil
    }

    // MARK: - Helpers

    /// Reads one of Mach-O's fixed-size, NUL-padded 16-byte name fields.
    ///
    /// The field is *not* guaranteed to be NUL-terminated when the name uses
    /// all sixteen bytes, so the terminator is appended rather than assumed.
    private static func nullPaddedName<FixedSizeCharacterTuple>(
        of fixedSizeCharacters: FixedSizeCharacterTuple
    ) -> String {
        var mutableCharacters = fixedSizeCharacters
        return withUnsafeBytes(of: &mutableCharacters) { rawBuffer in
            var characters: [CChar] = []
            characters.reserveCapacity(rawBuffer.count + 1)
            for byte in rawBuffer {
                if byte == 0 { break }
                characters.append(CChar(bitPattern: byte))
            }
            characters.append(0)
            return String(cString: characters)
        }
    }
}

#endif
