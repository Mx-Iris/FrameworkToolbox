import Foundation
import FrameworkToolbox
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

extension FrameworkToolbox<URL> {
    private struct DirectorySequence: Sequence {
        let enumerator: FileManager.DirectoryEnumerator?

        init(url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: mask)
            self.enumerator = enumerator
        }

        func makeIterator() -> AnyIterator<URL> {
            .init {
                enumerator?.nextObject() as? URL
            }
        }
    }

    public func enumerator(includingPropertiesForKeys keys: [URLResourceKey]? = nil, options mask: FileManager.DirectoryEnumerationOptions = []) -> some Sequence<URL> {
        return DirectorySequence(url: base, includingPropertiesForKeys: keys, options: mask)
    }

    // MARK: - File System Checks

    /// A Boolean value indicating whether the resource is a directory.
    @inlinable
    public var isDirectory: Bool {
        (try? base.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// A Boolean value indicating whether the resource is a regular file.
    @inlinable
    public var isFile: Bool {
        (try? base.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// A Boolean value indicating whether the file exists at this URL.
    @inlinable
    public var isExists: Bool {
        FileManager.default.fileExists(atPath: base.path)
    }

    // MARK: - Path Convenience

    /// The name of the URL (`lastPathComponent`).
    @inlinable
    public var name: String {
        base.lastPathComponent
    }

    /// The name excluding the path extension.
    @inlinable
    public var nameExcludingExtension: String {
        base.deletingPathExtension().lastPathComponent
    }

    /// The parent directory URL, or `nil` if there is no parent.
    @inlinable
    public var parent: URL? {
        let parent = base.deletingLastPathComponent()
        guard parent.path != base.path else { return nil }
        return parent
    }

    /// The query items of the URL.
    @inlinable
    public var queryItems: [URLQueryItem]? {
        URLComponents(url: base, resolvingAgainstBaseURL: false)?.queryItems
    }

    // MARK: - Path Relationships

    /// Returns `true` if this file URL is a parent of the given URL.
    ///
    /// - Parameter url: The URL to check.
    @inlinable
    public func isParent(of url: URL) -> Bool {
        guard base.isFileURL, url.isFileURL else { return false }
        let selfPath = base.standardizedFileURL.path
        let otherPath = url.standardizedFileURL.path
        let normalizedSelfPath = selfPath.hasSuffix("/") ? selfPath : selfPath + "/"
        return otherPath.hasPrefix(normalizedSelfPath)
    }

    /// Returns `true` if this file URL is a child of the given URL.
    ///
    /// - Parameter url: The URL to check.
    @inlinable
    public func isChild(of url: URL) -> Bool {
        Self(url).isParent(of: base)
    }
    
    // MARK: - URLResourceValues Dynamic Member Lookup

    /// Access any `URLResourceValues` property via key path.
    ///
    /// Example: `url.box.isSymbolicLink`, `url.box.fileSize`, `url.box.creationDate`.
    ///
    /// The corresponding `URLResourceKey` is looked up from `keyPathToResourceKey`.
    /// Properties that are not registered in that table return `nil`.
    ///
    /// Since every property on `URLResourceValues` is already optional, the
    /// subscript is constrained to `KeyPath<URLResourceValues, Wrapped?>` so
    /// the return type stays a single-level `Wrapped?` instead of `Wrapped??`.
    public subscript<Wrapped>(dynamicMember keyPath: KeyPath<URLResourceValues, Wrapped?>) -> Wrapped? {
        guard let resourceKey = Self.resourceKey(for: keyPath),
              let values = try? base.resourceValues(forKeys: [resourceKey])
        else {
            return nil
        }
        return values[keyPath: keyPath]
    }

    /// Fetches multiple `URLResourceValues` properties in a single underlying
    /// `resourceValues(forKeys:)` call — one system call instead of N.
    ///
    /// Example:
    /// ```swift
    /// let (size, created, modified) = url.box.resourceValues(
    ///     \.fileSize, \.creationDate, \.contentModificationDate
    /// )
    /// ```
    ///
    /// Any key path not registered in `keyPathToResourceKey` is skipped from
    /// the fetch, and its slot in the returned tuple is `nil`. If the call
    /// itself throws (file gone, permission denied, etc.), every slot is `nil`.
    public func resourceValues<each Value>(
        _ keyPaths: repeat KeyPath<URLResourceValues, (each Value)?>
    ) -> (repeat (each Value)?) {
        var keys: Set<URLResourceKey> = []
        for keyPath in repeat each keyPaths {
            if let key = Self.resourceKey(for: keyPath) {
                keys.insert(key)
            }
        }
        guard let values = try? base.resourceValues(forKeys: keys) else {
            return (repeat Optional<each Value>.none)
        }
        return (repeat values[keyPath: each keyPaths])
    }

    private static func resourceKey(for keyPath: PartialKeyPath<URLResourceValues>) -> URLResourceKey? {
        keyPathToResourceKey[keyPath]
    }

    /// Maps `URLResourceValues` key paths to their corresponding `URLResourceKey`.
    ///
    /// Swift's `KeyPath` cannot be reflected back to a property name at runtime
    /// (`_kvcKeyPathString` only works on `@objc` types), so we bridge between
    /// `KeyPath<URLResourceValues, _>` and `URLResourceKey` with an explicit
    /// table. Add new entries here when a new resource value is needed.
    private static let keyPathToResourceKey: [PartialKeyPath<URLResourceValues>: URLResourceKey] = {
        var map: [PartialKeyPath<URLResourceValues>: URLResourceKey] = [
            // Naming
            \.name: .nameKey,
            \.localizedName: .localizedNameKey,

            // Type
            \.isRegularFile: .isRegularFileKey,
            \.isDirectory: .isDirectoryKey,
            \.isSymbolicLink: .isSymbolicLinkKey,
            \.isVolume: .isVolumeKey,
            \.isPackage: .isPackageKey,
            \.isApplication: .isApplicationKey,
            \.isAliasFile: .isAliasFileKey,
            \.localizedTypeDescription: .localizedTypeDescriptionKey,
            \.typeIdentifier: .typeIdentifierKey,
            \.fileResourceType: .fileResourceTypeKey,

            // Permissions / visibility
            \.isExecutable: .isExecutableKey,
            \.isReadable: .isReadableKey,
            \.isWritable: .isWritableKey,
            \.isHidden: .isHiddenKey,
            \.hasHiddenExtension: .hasHiddenExtensionKey,
            \.isUserImmutable: .isUserImmutableKey,
            \.isSystemImmutable: .isSystemImmutableKey,
            \.fileSecurity: .fileSecurityKey,

            // Dates
            \.creationDate: .creationDateKey,
            \.contentAccessDate: .contentAccessDateKey,
            \.contentModificationDate: .contentModificationDateKey,
            \.attributeModificationDate: .attributeModificationDateKey,
            \.addedToDirectoryDate: .addedToDirectoryDateKey,

            // Sizes
            \.fileSize: .fileSizeKey,
            \.fileAllocatedSize: .fileAllocatedSizeKey,
            \.totalFileSize: .totalFileSizeKey,
            \.totalFileAllocatedSize: .totalFileAllocatedSizeKey,
            \.preferredIOBlockSize: .preferredIOBlockSizeKey,

            // Paths / identifiers
            \.path: .pathKey,
            \.canonicalPath: .canonicalPathKey,
            \.fileResourceIdentifier: .fileResourceIdentifierKey,
            \.volumeIdentifier: .volumeIdentifierKey,
            \.generationIdentifier: .generationIdentifierKey,
            \.documentIdentifier: .documentIdentifierKey,

            // Hierarchy
            \.parentDirectory: .parentDirectoryURLKey,
            \.volume: .volumeURLKey,
            \.linkCount: .linkCountKey,

            // Backup / mount
            \.isExcludedFromBackup: .isExcludedFromBackupKey,
            \.isMountTrigger: .isMountTriggerKey,

            // Labels
            \.labelNumber: .labelNumberKey,
            \.localizedLabel: .localizedLabelKey,

            // Volume — base level
            \.volumeLocalizedFormatDescription: .volumeLocalizedFormatDescriptionKey,
            \.volumeTotalCapacity: .volumeTotalCapacityKey,
            \.volumeAvailableCapacity: .volumeAvailableCapacityKey,
            \.volumeResourceCount: .volumeResourceCountKey,
            \.volumeSupportsPersistentIDs: .volumeSupportsPersistentIDsKey,
            \.volumeSupportsSymbolicLinks: .volumeSupportsSymbolicLinksKey,
            \.volumeSupportsHardLinks: .volumeSupportsHardLinksKey,
            \.volumeSupportsJournaling: .volumeSupportsJournalingKey,
            \.volumeIsJournaling: .volumeIsJournalingKey,
            \.volumeSupportsSparseFiles: .volumeSupportsSparseFilesKey,
            \.volumeSupportsZeroRuns: .volumeSupportsZeroRunsKey,
            \.volumeSupportsCaseSensitiveNames: .volumeSupportsCaseSensitiveNamesKey,
            \.volumeSupportsCasePreservedNames: .volumeSupportsCasePreservedNamesKey,
            \.volumeSupportsRootDirectoryDates: .volumeSupportsRootDirectoryDatesKey,
            \.volumeSupportsVolumeSizes: .volumeSupportsVolumeSizesKey,
            \.volumeSupportsRenaming: .volumeSupportsRenamingKey,
            \.volumeSupportsAdvisoryFileLocking: .volumeSupportsAdvisoryFileLockingKey,
            \.volumeSupportsExtendedSecurity: .volumeSupportsExtendedSecurityKey,
            \.volumeIsBrowsable: .volumeIsBrowsableKey,
            \.volumeMaximumFileSize: .volumeMaximumFileSizeKey,
            \.volumeIsEjectable: .volumeIsEjectableKey,
            \.volumeIsRemovable: .volumeIsRemovableKey,
            \.volumeIsInternal: .volumeIsInternalKey,
            \.volumeIsAutomounted: .volumeIsAutomountedKey,
            \.volumeIsLocal: .volumeIsLocalKey,
            \.volumeIsReadOnly: .volumeIsReadOnlyKey,
            \.volumeCreationDate: .volumeCreationDateKey,
            \.volumeURLForRemounting: .volumeURLForRemountingKey,
            \.volumeUUIDString: .volumeUUIDStringKey,
            \.volumeName: .volumeNameKey,
            \.volumeLocalizedName: .volumeLocalizedNameKey,
            \.volumeIsEncrypted: .volumeIsEncryptedKey,
            \.volumeIsRootFileSystem: .volumeIsRootFileSystemKey,
            \.volumeSupportsCompression: .volumeSupportsCompressionKey,
            \.volumeSupportsFileCloning: .volumeSupportsFileCloningKey,
            \.volumeSupportsSwapRenaming: .volumeSupportsSwapRenamingKey,
            \.volumeSupportsExclusiveRenaming: .volumeSupportsExclusiveRenamingKey,
            \.volumeSupportsImmutableFiles: .volumeSupportsImmutableFilesKey,
            \.volumeSupportsAccessPermissions: .volumeSupportsAccessPermissionsKey,

            // Ubiquitous (iCloud)
            \.isUbiquitousItem: .isUbiquitousItemKey,
            \.ubiquitousItemHasUnresolvedConflicts: .ubiquitousItemHasUnresolvedConflictsKey,
            \.ubiquitousItemIsDownloading: .ubiquitousItemIsDownloadingKey,
            \.ubiquitousItemIsUploaded: .ubiquitousItemIsUploadedKey,
            \.ubiquitousItemIsUploading: .ubiquitousItemIsUploadingKey,
            \.ubiquitousItemDownloadingStatus: .ubiquitousItemDownloadingStatusKey,
            \.ubiquitousItemDownloadingError: .ubiquitousItemDownloadingErrorKey,
            \.ubiquitousItemUploadingError: .ubiquitousItemUploadingErrorKey,
            \.ubiquitousItemDownloadRequested: .ubiquitousItemDownloadRequestedKey,
            \.ubiquitousItemContainerDisplayName: .ubiquitousItemContainerDisplayNameKey,
        ]

        // macOS-only properties
        #if os(macOS)
        map[\.applicationIsScriptable] = .applicationIsScriptableKey
        map[\.tagNames] = .tagNamesKey
        map[\.quarantineProperties] = .quarantinePropertiesKey
        #endif

        // Not available on tvOS / watchOS
        #if !os(tvOS) && !os(watchOS)
        map[\.volumeAvailableCapacityForImportantUsage] = .volumeAvailableCapacityForImportantUsageKey
        map[\.volumeAvailableCapacityForOpportunisticUsage] = .volumeAvailableCapacityForOpportunisticUsageKey
        map[\.ubiquitousItemIsShared] = .ubiquitousItemIsSharedKey
        map[\.ubiquitousSharedItemCurrentUserRole] = .ubiquitousSharedItemCurrentUserRoleKey
        map[\.ubiquitousSharedItemCurrentUserPermissions] = .ubiquitousSharedItemCurrentUserPermissionsKey
        map[\.ubiquitousSharedItemOwnerNameComponents] = .ubiquitousSharedItemOwnerNameComponentsKey
        map[\.ubiquitousSharedItemMostRecentEditorNameComponents] = .ubiquitousSharedItemMostRecentEditorNameComponentsKey
        #endif

        // fileProtection: macOS 11.0+, iOS 9.0+ (macOS needs runtime check)
        if #available(macOS 11.0, iOS 9.0, tvOS 9.0, watchOS 2.0, *) {
            map[\.fileProtection] = .fileProtectionKey
        }

        // macOS 11 / iOS 14 / tvOS 14 / watchOS 7
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
            map[\.fileContentIdentifier] = .fileContentIdentifierKey
            map[\.mayHaveExtendedAttributes] = .mayHaveExtendedAttributesKey
            map[\.isPurgeable] = .isPurgeableKey
            map[\.isSparse] = .isSparseKey
            map[\.mayShareFileContent] = .mayShareFileContentKey
        }

        // macOS 11.3 / iOS 14.5 / tvOS 14.5 / watchOS 7.4
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, watchOS 7.4, *) {
            map[\.ubiquitousItemIsExcludedFromSync] = .ubiquitousItemIsExcludedFromSyncKey
        }

        // macOS 13.3 / iOS 16.4 / tvOS 16.4 / watchOS 9.4
        if #available(macOS 13.3, iOS 16.4, tvOS 16.4, watchOS 9.4, *) {
            map[\.fileIdentifier] = .fileIdentifierKey
            map[\.volumeTypeName] = .volumeTypeNameKey
            map[\.volumeSubtype] = .volumeSubtypeKey
            map[\.volumeMountFromLocation] = .volumeMountFromLocationKey
        }

        // macOS 14.0 / iOS 17.0 / tvOS 17.0 / watchOS 10.0
        if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
            map[\.directoryEntryCount] = .directoryEntryCountKey
        }

        // contentType — declared in UniformTypeIdentifiers (macOS 11 / iOS 14 / tvOS 14 / watchOS 7)
        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
            map[\.contentType] = .contentTypeKey
        }
        #endif

        return map
    }()
}
