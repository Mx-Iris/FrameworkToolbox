#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import os

// MARK: - Encoding Normalisation

/// Compares Objective-C method type encodings for signature equivalence.
///
/// Two encodings describing the same signature are not necessarily the same
/// string. The runtime reports an offset-annotated flavour (`v28@0:8@16B24`)
/// while a hand-written or derived encoding is usually bare (`v@:@B`). The
/// offsets are a function of the types that precede them, so they carry nothing
/// the comparison needs; stripping them compares exactly the part that matters.
public enum ObjCTypeEncodingNormalization {

    /// Whether two encodings describe the same signature.
    public static func matches(_ leftEncoding: String, _ rightEncoding: String) -> Bool {
        normalized(leftEncoding) == normalized(rightEncoding)
    }

    /// Drops frame offsets and folds the two spellings of `BOOL`.
    ///
    /// `BOOL` is C `bool` (`B`) on arm64 and `signed char` (`c`) on x86_64.
    /// Swift's `Bool` bridges correctly to whichever the platform uses, so an
    /// encoding derived from a Swift `Bool` must be accepted against either.
    /// The two share a size and an argument-passing rule, so treating them as
    /// equivalent loses no ABI information. The same fold makes `Int8` and
    /// `Bool` indistinguishable, which is harmless for the same reason.
    public static func normalized(_ encoding: String) -> String {
        var result = ""
        result.reserveCapacity(encoding.count)
        for character in encoding {
            if character.isNumber { continue }
            result.append(character == "c" ? "B" : character)
        }
        return result
    }
}

// MARK: - Inspection

/// Reads method metadata out of classes that are only known by name.
///
/// The classes this module targets live in the host process and have no header,
/// so every fact about them has to come from the runtime rather than from the
/// compiler. This is the read-only half of that: use it to discover a live
/// signature, or to check one before assuming it.
public enum RuntimeMethodInspector {

    /// The type encoding a class currently reports for a selector.
    ///
    /// - Returns: `nil` when the class is absent from this process or does not
    ///   implement the selector.
    public static func typeEncoding(
        forClassNamed className: String,
        selector: Selector,
        isInstanceMethod: Bool = true
    ) -> String? {
        guard let resolvedClass = objc_getClass(className) as? AnyClass else { return nil }
        return typeEncoding(forClass: resolvedClass, selector: selector, isInstanceMethod: isInstanceMethod)
    }

    /// The type encoding a class currently reports for a selector.
    public static func typeEncoding(
        forClass resolvedClass: AnyClass,
        selector: Selector,
        isInstanceMethod: Bool = true
    ) -> String? {
        let method = isInstanceMethod
            ? class_getInstanceMethod(resolvedClass, selector)
            : class_getClassMethod(resolvedClass, selector)
        guard let resolvedMethod = method,
              let encoding = method_getTypeEncoding(resolvedMethod)
        else { return nil }
        return String(cString: encoding)
    }

    /// Whether the host has this method with the signature the caller is about
    /// to assume.
    ///
    /// Calling a method through a hand-formed `@convention(c)` pointer needs the
    /// same signature check that replacing one does. Getting it wrong when
    /// *calling* is if anything worse: the arguments are marshalled straight
    /// into the host's registers and the crash lands somewhere with nothing
    /// pointing back at this code. Check first, and skip the call when the host
    /// does not match.
    public static func hasMethod(
        className: String,
        selector: Selector,
        matchingTypeEncoding expectedTypeEncoding: String,
        isInstanceMethod: Bool = true
    ) -> Bool {
        guard let liveTypeEncoding = typeEncoding(
            forClassNamed: className,
            selector: selector,
            isInstanceMethod: isInstanceMethod
        ) else { return false }
        return ObjCTypeEncodingNormalization.matches(expectedTypeEncoding, liveTypeEncoding)
    }
}

// MARK: - Hook Installation

/// Replaces method implementations on classes that are only known by name, with
/// the signature checked against the live process first.
///
/// ## Relationship to `DynamicSubclass`
///
/// ``DynamicSubclass`` swizzles one instance's `isa` and is the better tool
/// whenever you hold the instances you want to affect. This one replaces the
/// implementation on the class itself, which is what you need when the target
/// class is not available at compile time, when instances are created by code
/// you do not control, and when the replacement must apply to instances that do
/// not exist yet. It is correspondingly blunter: there is no uninstall, and the
/// change is process-wide.
///
/// ## The signature check
///
/// Every descriptor carries the type encoding its replacement block was written
/// against. Installation compares that against what the class reports now and
/// refuses the whole batch on any mismatch. This is the single most valuable
/// guarantee here: a method whose parameter list changed under you would
/// otherwise be called through a block built for the old signature, which
/// corrupts registers and crashes a process that never asked to be involved.
///
/// When the descriptors come from `@RuntimeClassHook`, the encoding is derived
/// from the block's own Swift signature at compile time, so the two cannot
/// disagree and the comparison is a genuine assertion about the host.
///
/// ## All or nothing
///
/// Every descriptor is resolved and checked before any implementation is
/// swapped. A half-installed batch is worse than none at all, because the host
/// then runs a mix of replaced and original behaviour that nobody designed.
public enum RuntimeMethodHook {

    // MARK: Descriptor

    /// One method implementation swap, described declaratively.
    ///
    /// The target is named by string and selector rather than by a compile-time
    /// symbol, because the class lives in the host process and is unavailable
    /// at build time.
    public struct Descriptor: Sendable {

        /// Name of the class that declares the method, resolved with
        /// `objc_getClass`.
        public let className: String

        /// Selector of the method to replace.
        public let selector: Selector

        /// Whether the method is an instance method (`true`) or a class method
        /// (`false`).
        public let isInstanceMethod: Bool

        /// The type encoding this descriptor's replacement was written against.
        ///
        /// Obtain it from the Swift signature via `@RuntimeClassHook` rather
        /// than by hand. When writing one manually, read the live value with
        /// ``RuntimeMethodInspector/typeEncoding(forClassNamed:selector:isInstanceMethod:)``
        /// instead of deriving it from a decompiler's rendering of the
        /// signature — an encoding whose length happens to match but whose
        /// contents are wrong passes every check here and then corrupts
        /// registers at call time.
        public let expectedTypeEncoding: String

        /// Builds the replacement implementation from the original one.
        ///
        /// Return `imp_implementationWithBlock` over a `@convention(block)`
        /// closure whose signature matches ``expectedTypeEncoding`` — the first
        /// block parameter is the receiver and the selector is *not* passed.
        /// Capture `originalImplementation` and cast it to a `@convention(c)`
        /// function type over the same signature to forward to the host.
        public let makeReplacement: @Sendable (_ originalImplementation: IMP) -> IMP

        public init(
            className: String,
            selector: Selector,
            isInstanceMethod: Bool = true,
            expectedTypeEncoding: String,
            makeReplacement: @escaping @Sendable (_ originalImplementation: IMP) -> IMP
        ) {
            self.className = className
            self.selector = selector
            self.isInstanceMethod = isInstanceMethod
            self.expectedTypeEncoding = expectedTypeEncoding
            self.makeReplacement = makeReplacement
        }
    }

    // MARK: Failure

    /// Why a batch was rejected. Nothing has been modified when one is thrown.
    public enum InstallationFailure: Error, CustomStringConvertible, Equatable {

        /// `objc_getClass` found no such class in this process.
        case classNotFound(className: String)

        /// The class exists but does not implement the selector.
        case methodNotFound(className: String, selectorName: String)

        /// The method exists but reports no type encoding, so the signature
        /// cannot be checked and the swap is refused.
        case typeEncodingMissing(className: String, selectorName: String)

        /// The live signature differs from what the replacement was written
        /// against — typically an operating-system update that changed the
        /// method.
        case typeEncodingMismatch(
            className: String,
            selectorName: String,
            expected: String,
            actual: String
        )

        /// This module already replaced that method. Installing again would
        /// chain the second replacement on top of the first, so each one's
        /// "original" would be the other's replacement.
        case alreadyInstalled(className: String, selectorName: String)

        /// The same method appears twice in one batch.
        case duplicateInBatch(className: String, selectorName: String)

        public var description: String {
            switch self {
            case .classNotFound(let className):
                return "class \(className) not found in this process"
            case .methodNotFound(let className, let selectorName):
                return "\(className) does not respond to \(selectorName)"
            case .typeEncodingMissing(let className, let selectorName):
                return "\(className) \(selectorName) has no type encoding"
            case .typeEncodingMismatch(let className, let selectorName, let expected, let actual):
                return "\(className) \(selectorName) signature changed — expected \(expected), found \(actual)"
            case .alreadyInstalled(let className, let selectorName):
                return "\(className) \(selectorName) is already hooked; installing again would chain replacements"
            case .duplicateInBatch(let className, let selectorName):
                return "\(className) \(selectorName) appears more than once in the same batch"
            }
        }
    }

    // MARK: Installation

    /// Checks every descriptor, then swaps every implementation.
    ///
    /// - Throws: ``InstallationFailure`` for the first descriptor that fails.
    ///   Nothing has been modified when this throws.
    public static func installAtomically(_ descriptors: [Descriptor]) throws {
        let checkedHooks = try check(descriptors)

        for checkedHook in checkedHooks {
            let originalImplementation = method_getImplementation(checkedHook.method)
            let replacementImplementation = checkedHook.descriptor.makeReplacement(originalImplementation)
            method_setImplementation(checkedHook.method, replacementImplementation)
            markInstalled(checkedHook.identity)
            os_log(
                .info,
                log: hookLog,
                "Installed hook %{public}@",
                checkedHook.descriptor.description
            )
        }
    }

    /// Checks a batch without installing anything.
    ///
    /// Useful for reporting host compatibility before any behaviour changes —
    /// for example to decide between hooking and staying dormant.
    public static func validate(_ descriptors: [Descriptor]) -> Result<Void, InstallationFailure> {
        do {
            _ = try check(descriptors)
            return .success(())
        } catch let failure as InstallationFailure {
            return .failure(failure)
        } catch {
            preconditionFailure("check(_:) only throws InstallationFailure")
        }
    }

    /// Whether this module has already replaced a given method.
    public static func isInstalled(className: String, selector: Selector, isInstanceMethod: Bool = true) -> Bool {
        let identity = MethodIdentity(
            className: className,
            selectorName: NSStringFromSelector(selector),
            isInstanceMethod: isInstanceMethod
        )
        sharedLockLock()
        defer { sharedLockUnlock() }
        return sharedInstalledMethods.contains(identity)
    }

    // MARK: Checking

    /// A descriptor that passed every check, carrying the resolved handle so
    /// the swap phase needs no further lookups.
    private struct CheckedHook {
        let descriptor: Descriptor
        let method: Method
        let identity: MethodIdentity
    }

    private static func check(_ descriptors: [Descriptor]) throws -> [CheckedHook] {
        var checkedHooks: [CheckedHook] = []
        var seenInThisBatch: Set<MethodIdentity> = []

        for descriptor in descriptors {
            let selectorName = NSStringFromSelector(descriptor.selector)
            let identity = MethodIdentity(
                className: descriptor.className,
                selectorName: selectorName,
                isInstanceMethod: descriptor.isInstanceMethod
            )

            guard seenInThisBatch.insert(identity).inserted else {
                throw InstallationFailure.duplicateInBatch(
                    className: descriptor.className,
                    selectorName: selectorName
                )
            }

            if isInstalled(identity) {
                throw InstallationFailure.alreadyInstalled(
                    className: descriptor.className,
                    selectorName: selectorName
                )
            }

            guard let resolvedClass = objc_getClass(descriptor.className) as? AnyClass else {
                throw InstallationFailure.classNotFound(className: descriptor.className)
            }

            let method = descriptor.isInstanceMethod
                ? class_getInstanceMethod(resolvedClass, descriptor.selector)
                : class_getClassMethod(resolvedClass, descriptor.selector)

            guard let resolvedMethod = method else {
                throw InstallationFailure.methodNotFound(
                    className: descriptor.className,
                    selectorName: selectorName
                )
            }

            guard let liveTypeEncodingCString = method_getTypeEncoding(resolvedMethod) else {
                throw InstallationFailure.typeEncodingMissing(
                    className: descriptor.className,
                    selectorName: selectorName
                )
            }

            let liveTypeEncoding = String(cString: liveTypeEncodingCString)
            guard ObjCTypeEncodingNormalization.matches(descriptor.expectedTypeEncoding, liveTypeEncoding) else {
                throw InstallationFailure.typeEncodingMismatch(
                    className: descriptor.className,
                    selectorName: selectorName,
                    expected: descriptor.expectedTypeEncoding,
                    actual: liveTypeEncoding
                )
            }

            checkedHooks.append(CheckedHook(descriptor: descriptor, method: resolvedMethod, identity: identity))
        }

        return checkedHooks
    }

    // MARK: Installed-Method Registry

    private struct MethodIdentity: Hashable {
        let className: String
        let selectorName: String
        let isInstanceMethod: Bool
    }

    // `os_unfair_lock` rather than `OSAllocatedUnfairLock` to stay within this
    // package's macOS 10.15 floor, matching `DynamicSubclass`.
    nonisolated(unsafe) private static var sharedLockStorage = os_unfair_lock_s()
    nonisolated(unsafe) private static var sharedInstalledMethods: Set<MethodIdentity> = []

    static let hookLog = OSLog(subsystem: "ObjCRuntimeToolbox", category: "RuntimeMethodHook")

    private static func sharedLockLock() {
        withUnsafeMutablePointer(to: &sharedLockStorage) { os_unfair_lock_lock($0) }
    }

    private static func sharedLockUnlock() {
        withUnsafeMutablePointer(to: &sharedLockStorage) { os_unfair_lock_unlock($0) }
    }

    private static func isInstalled(_ identity: MethodIdentity) -> Bool {
        sharedLockLock()
        defer { sharedLockUnlock() }
        return sharedInstalledMethods.contains(identity)
    }

    private static func markInstalled(_ identity: MethodIdentity) {
        sharedLockLock()
        sharedInstalledMethods.insert(identity)
        sharedLockUnlock()
    }
}

extension RuntimeMethodHook.Descriptor: CustomStringConvertible {
    public var description: String {
        let methodTypeMarker = isInstanceMethod ? "-" : "+"
        return "\(methodTypeMarker)[\(className) \(NSStringFromSelector(selector))]"
    }
}

#endif
