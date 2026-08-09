#if canImport(Darwin) && _pointerBitWidth(_64)

import Darwin
import MachO
import OSToolbox
import PointerAuthenticationSupport

/// Applies the interposes declared with `@DyldDynamicInterpose`, and takes
/// them back again.
///
/// This is a revival of `dyld_dynamic_interpose`, whose body has been an
/// unconditional `return` since dyld4 (`libdyld/libdyldGlue.cpp`, annotated
/// with `rdar://74287303`). The algorithm is the one dyld2 used in
/// `ImageLoaderMachOClassic::dynamicInterpose`: walk an image's symbol pointer
/// sections and overwrite every slot whose current value is the address of the
/// function being replaced.
///
/// ```swift
/// @DyldDynamicInterpose(puts)
/// func interposedPuts(_ string: UnsafePointer<CChar>?) -> Int32 {
///     fputs("[hooked] ", stdout)
///     return puts(string)
/// }
///
/// DyldDynamicInterpose.applyAll()
/// // …
/// DyldDynamicInterpose.revertAll()
/// ```
///
/// ## What it can and cannot reach
///
/// Only indirection slots are rewritten. Direct calls, inlined calls, and
/// function pointers a program has already copied somewhere else keep going to
/// the original — dyld's own header carries the same warning. In particular,
/// calls *between* shared-cache dylibs are largely direct branches, so
/// interposing a libSystem function realistically only redirects calls made
/// from images you built yourself.
///
/// ## Concurrency
///
/// Each slot is a naturally aligned, pointer-sized store, so a thread calling
/// through a slot while it is being rewritten observes either the old or the
/// new function — never a torn value. The bookkeeping needed for
/// ``revertAll()`` is serialised with a process-wide lock.
public enum DyldDynamicInterpose {

    // MARK: - Reading the registry

    /// The tuples `@DyldDynamicInterpose` planted in the image containing the
    /// call site.
    public static func registeredTuples(
        declaredIn declaringImage: UnsafeRawPointer = #dsohandle
    ) -> [DyldDynamicInterposeTuple] {
        DyldDynamicInterposeRegistry.registeredTuples(declaredIn: declaringImage)
    }

    // MARK: - Applying

    /// Applies every interpose declared with `@DyldDynamicInterpose` in the
    /// image containing the call site.
    ///
    /// - Parameters:
    ///   - targetImages: Which images to rewrite. Defaults to every image
    ///     mapped into the process.
    ///   - excludingDeclaringImage: When `true` (the default) the declaring
    ///     image is left untouched, so a replacement can call the function it
    ///     replaces without recursing into itself.
    ///   - declaringImage: The image whose registry to read. Defaults to the
    ///     image containing the call site.
    @discardableResult
    public static func applyAll(
        to targetImages: DyldDynamicInterposeTargetImages = .allImages,
        excludingDeclaringImage: Bool = true,
        declaredIn declaringImage: UnsafeRawPointer = #dsohandle
    ) -> DyldDynamicInterposeReport {
        let tuples = registeredTuples(declaredIn: declaringImage)
        guard !tuples.isEmpty else { return .empty }
        return apply(
            tuples,
            to: targetImages,
            excludingImages: excludingDeclaringImage ? [declaringImage] : []
        )
    }

    /// Applies an explicit list of tuples, for callers assembling them at
    /// runtime rather than through the macro.
    @discardableResult
    public static func apply(
        _ tuples: [DyldDynamicInterposeTuple],
        to targetImages: DyldDynamicInterposeTargetImages = .allImages,
        excludingImages excludedImages: [UnsafeRawPointer] = []
    ) -> DyldDynamicInterposeReport {
        guard !tuples.isEmpty else { return .empty }

        var tuplesByStrippedReplacee: [UInt: DyldDynamicInterposeTuple] = [:]
        for tuple in tuples {
            let strippedReplacee = pointerAuthenticationStripCodePointer(UInt(bitPattern: tuple.replacee))
            tuplesByStrippedReplacee[strippedReplacee] = tuple
        }

        var rewrittenSlots: [DyldDynamicInterposeReport.RewrittenSlot] = []
        var skippedSlots: [DyldDynamicInterposeReport.SkippedSlot] = []
        var newRecords: [RewrittenSlotRecord] = []

        for image in MachOImageScanner.loadedImages() {
            guard targetImages.matches(image) else { continue }
            guard !excludedImages.contains(UnsafeRawPointer(image.machHeader)) else { continue }

            rewriteSymbolPointerSections(
                of: image,
                tuplesByStrippedReplacee: tuplesByStrippedReplacee,
                rewrittenSlots: &rewrittenSlots,
                skippedSlots: &skippedSlots,
                records: &newRecords
            )
        }

        if !newRecords.isEmpty {
            rewrittenSlotRecordsByApplicationOrder.withLock { records in
                records.append(contentsOf: newRecords)
            }
        }
        return DyldDynamicInterposeReport(rewrittenSlots: rewrittenSlots, skippedSlots: skippedSlots)
    }

    // MARK: - Reverting

    /// Restores every slot this library has rewritten, newest first.
    ///
    /// Slots whose contents have since been changed by something else are left
    /// alone and reported as
    /// ``DyldDynamicInterposeReport/SkippedSlot/Reason/slotNoLongerHoldsInterposedValue``,
    /// along with their bookkeeping, so a later call can try again.
    @discardableResult
    public static func revertAll() -> DyldDynamicInterposeReport {
        var rewrittenSlots: [DyldDynamicInterposeReport.RewrittenSlot] = []
        var skippedSlots: [DyldDynamicInterposeReport.SkippedSlot] = []

        rewrittenSlotRecordsByApplicationOrder.withLock { records in
            var unrestoredRecords: [RewrittenSlotRecord] = []

            for record in records.reversed() {
                let slotAddress = UInt(bitPattern: record.slot)

                guard record.slot.pointee == record.interposedValue else {
                    skippedSlots.append(
                        DyldDynamicInterposeReport.SkippedSlot(
                            imagePath: record.imagePath,
                            segmentName: record.segmentName,
                            sectionName: record.sectionName,
                            slotAddress: slotAddress,
                            reason: .slotNoLongerHoldsInterposedValue
                        )
                    )
                    unrestoredRecords.append(record)
                    continue
                }

                let failureErrorNumber = MachOImageScanner.withWritableMemory(
                    startAddress: slotAddress,
                    endAddress: slotAddress &+ UInt(MemoryLayout<UInt>.size),
                    restoringProtection: record.protectionToRestore
                ) {
                    record.slot.pointee = record.originalValue
                }

                if let errorNumber = failureErrorNumber {
                    skippedSlots.append(
                        DyldDynamicInterposeReport.SkippedSlot(
                            imagePath: record.imagePath,
                            segmentName: record.segmentName,
                            sectionName: record.sectionName,
                            slotAddress: slotAddress,
                            reason: .memoryProtectionChangeFailed(errorNumber: errorNumber)
                        )
                    )
                    unrestoredRecords.append(record)
                } else {
                    rewrittenSlots.append(
                        DyldDynamicInterposeReport.RewrittenSlot(
                            imagePath: record.imagePath,
                            segmentName: record.segmentName,
                            sectionName: record.sectionName,
                            slotAddress: slotAddress,
                            previousValue: record.interposedValue,
                            newValue: record.originalValue
                        )
                    )
                }
            }

            records = unrestoredRecords.reversed()
        }

        return DyldDynamicInterposeReport(rewrittenSlots: rewrittenSlots, skippedSlots: skippedSlots)
    }

    // MARK: - Rewriting one image

    private static func rewriteSymbolPointerSections(
        of image: LoadedMachOImage,
        tuplesByStrippedReplacee: [UInt: DyldDynamicInterposeTuple],
        rewrittenSlots: inout [DyldDynamicInterposeReport.RewrittenSlot],
        skippedSlots: inout [DyldDynamicInterposeReport.SkippedSlot],
        records: inout [RewrittenSlotRecord]
    ) {
        for section in MachOImageScanner.symbolPointerSections(of: image) {
            var pendingWrites: [PendingSlotWrite] = []

            for slotIndex in 0 ..< section.slotCount {
                let currentValue = section.firstSlot[slotIndex]
                guard currentValue != 0 else { continue }

                let strippedCurrentValue = pointerAuthenticationStripCodePointer(currentValue)
                guard let tuple = tuplesByStrippedReplacee[strippedCurrentValue] else { continue }

                let slotAddress = UInt(bitPattern: section.firstSlot + slotIndex)
                let strippedReplacement = pointerAuthenticationStripCodePointer(
                    UInt(bitPattern: tuple.replacement)
                )

                let newValue: UInt
                if currentValue == strippedCurrentValue {
                    // Plain pointer — the only case on arm64 and x86_64, and
                    // also what arm64e `__auth_got` slots decay to inside a
                    // process that does not itself run the arm64e ABI.
                    newValue = strippedReplacement
                } else {
                    // Signed pointer. Confirm the assumed schema (instruction
                    // key, address diversity, no extra discriminator) really
                    // reproduces the bits already in the slot before trusting
                    // it to sign the replacement; guessing wrong here would
                    // write a value the hardware faults on at the call site.
                    let reproducedValue = pointerAuthenticationSignCodePointerForSlot(
                        strippedCurrentValue,
                        slotAddress
                    )
                    guard reproducedValue == currentValue else {
                        skippedSlots.append(
                            DyldDynamicInterposeReport.SkippedSlot(
                                imagePath: image.path,
                                segmentName: section.segmentName,
                                sectionName: section.sectionName,
                                slotAddress: slotAddress,
                                reason: .pointerAuthenticationSchemaNotRecognized
                            )
                        )
                        continue
                    }
                    newValue = pointerAuthenticationSignCodePointerForSlot(strippedReplacement, slotAddress)
                }

                guard newValue != currentValue else { continue }
                pendingWrites.append(
                    PendingSlotWrite(slotIndex: slotIndex, previousValue: currentValue, newValue: newValue)
                )
            }

            guard !pendingWrites.isEmpty else { continue }

            let sectionStartAddress = UInt(bitPattern: section.firstSlot)
            let sectionEndAddress = sectionStartAddress
                &+ UInt(section.slotCount * MemoryLayout<UInt>.size)

            let failureErrorNumber = MachOImageScanner.withWritableMemory(
                startAddress: sectionStartAddress,
                endAddress: sectionEndAddress,
                restoringProtection: section.protectionToRestore
            ) {
                for pendingWrite in pendingWrites {
                    section.firstSlot[pendingWrite.slotIndex] = pendingWrite.newValue
                }
            }

            for pendingWrite in pendingWrites {
                let slotAddress = UInt(bitPattern: section.firstSlot + pendingWrite.slotIndex)

                if let errorNumber = failureErrorNumber {
                    skippedSlots.append(
                        DyldDynamicInterposeReport.SkippedSlot(
                            imagePath: image.path,
                            segmentName: section.segmentName,
                            sectionName: section.sectionName,
                            slotAddress: slotAddress,
                            reason: .memoryProtectionChangeFailed(errorNumber: errorNumber)
                        )
                    )
                    continue
                }

                rewrittenSlots.append(
                    DyldDynamicInterposeReport.RewrittenSlot(
                        imagePath: image.path,
                        segmentName: section.segmentName,
                        sectionName: section.sectionName,
                        slotAddress: slotAddress,
                        previousValue: pendingWrite.previousValue,
                        newValue: pendingWrite.newValue
                    )
                )
                records.append(
                    RewrittenSlotRecord(
                        imagePath: image.path,
                        segmentName: section.segmentName,
                        sectionName: section.sectionName,
                        slot: section.firstSlot + pendingWrite.slotIndex,
                        originalValue: pendingWrite.previousValue,
                        interposedValue: pendingWrite.newValue,
                        protectionToRestore: section.protectionToRestore
                    )
                )
            }
        }
    }
}

// MARK: - Internal bookkeeping

private struct PendingSlotWrite {
    let slotIndex: Int
    let previousValue: UInt
    let newValue: UInt
}

/// Everything needed to put one slot back the way it was — which dyld's own
/// dynamic interposing never kept, and therefore could never undo.
private struct RewrittenSlotRecord {
    let imagePath: String
    let segmentName: String
    let sectionName: String
    let slot: UnsafeMutablePointer<UInt>
    let originalValue: UInt
    let interposedValue: UInt
    let protectionToRestore: Int32
}

/// The records needed to undo what ``DyldDynamicInterpose/applyAll(to:excludingDeclaringImage:declaredIn:)``
/// wrote, guarded by `OSToolbox`'s `Mutex` — an `os_unfair_lock` and its value
/// in one allocation, which is what this used to hand-roll.
private let rewrittenSlotRecordsByApplicationOrder = Mutex<[RewrittenSlotRecord]>([])

#endif
