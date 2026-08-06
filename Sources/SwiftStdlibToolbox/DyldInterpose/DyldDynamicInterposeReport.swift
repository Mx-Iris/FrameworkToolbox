#if canImport(Darwin) && _pointerBitWidth(_64)

/// What a call to ``DyldDynamicInterpose`` actually did.
///
/// Dynamic interposing is best-effort by nature — how many slots exist for a
/// given function depends on how the images calling it were compiled — so the
/// report is the only honest way to tell whether anything happened.
public struct DyldDynamicInterposeReport: Sendable, Equatable {
    /// A symbol pointer slot whose contents were replaced.
    public struct RewrittenSlot: Sendable, Equatable {
        public let imagePath: String
        public let segmentName: String
        public let sectionName: String
        public let slotAddress: UInt
        public let previousValue: UInt
        public let newValue: UInt
    }

    /// A slot that matched the function being replaced but could not be written.
    public struct SkippedSlot: Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            /// `mprotect` refused to make the containing pages writable.
            case memoryProtectionChangeFailed(errorNumber: Int32)

            /// The slot holds a signed pointer whose signing schema could not
            /// be reproduced, so re-signing the replacement would have written
            /// a value the hardware would later reject. See
            /// `PointerAuthenticationSupport`.
            case pointerAuthenticationSchemaNotRecognized

            /// Reverting only: the slot no longer holds the value this library
            /// wrote, so something else has taken it over and restoring the
            /// original would clobber that.
            case slotNoLongerHoldsInterposedValue
        }

        public let imagePath: String
        public let segmentName: String
        public let sectionName: String
        public let slotAddress: UInt
        public let reason: Reason
    }

    public let rewrittenSlots: [RewrittenSlot]
    public let skippedSlots: [SkippedSlot]

    public static let empty = DyldDynamicInterposeReport(rewrittenSlots: [], skippedSlots: [])

    public init(rewrittenSlots: [RewrittenSlot], skippedSlots: [SkippedSlot]) {
        self.rewrittenSlots = rewrittenSlots
        self.skippedSlots = skippedSlots
    }

    /// `true` when nothing was rewritten and nothing was skipped.
    public var isEmpty: Bool {
        rewrittenSlots.isEmpty && skippedSlots.isEmpty
    }

    /// The distinct images in which at least one slot was rewritten.
    public var affectedImagePaths: [String] {
        var seenPaths: Set<String> = []
        var orderedPaths: [String] = []
        for slot in rewrittenSlots where seenPaths.insert(slot.imagePath).inserted {
            orderedPaths.append(slot.imagePath)
        }
        return orderedPaths
    }
}

extension DyldDynamicInterposeReport: CustomStringConvertible {
    public var description: String {
        var lines: [String] = [
            "DyldDynamicInterposeReport(rewritten: \(rewrittenSlots.count), skipped: \(skippedSlots.count))",
        ]
        for slot in rewrittenSlots {
            lines.append(
                "  rewrote \(slot.segmentName),\(slot.sectionName) "
                    + "slot 0x\(String(slot.slotAddress, radix: 16)): "
                    + "0x\(String(slot.previousValue, radix: 16)) -> 0x\(String(slot.newValue, radix: 16)) "
                    + "in \(slot.imagePath)"
            )
        }
        for slot in skippedSlots {
            lines.append(
                "  skipped \(slot.segmentName),\(slot.sectionName) "
                    + "slot 0x\(String(slot.slotAddress, radix: 16)): \(slot.reason) "
                    + "in \(slot.imagePath)"
            )
        }
        return lines.joined(separator: "\n")
    }
}

#endif
