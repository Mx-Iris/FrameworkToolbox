#if os(macOS)
import Foundation
import Testing

/// Guards the topology that keeps `.dynamic` from spreading.
///
/// `ObjCRuntimeToolbox` is a `.dynamic` product, and Xcode builds a dynamic
/// product's transitive targets as shared dynamic frameworks for the whole
/// workspace. A runtime target dependency added to the `ObjCRuntimeToolbox`
/// target therefore switches every client — including executables that never
/// import the module — to @rpath-linking that dependency, and nested
/// executables without an rpath (daemons, XPC helpers) crash at dyld time.
/// That is what broke RuntimeViewer's SMAppService daemon in 0.10.0, when an
/// `OSToolbox` dependency dragged `OSToolbox` and `FrameworkToolbox` into the
/// dynamic closure. See the `objc-runtime-toolbox-self-contained-leaf`
/// evolution proposal.
///
/// The property guarded here is the *source* of that failure — the target has
/// no runtime target dependency — because the failure itself is Xcode
/// behaviour that a pure SwiftPM build cannot reproduce.
@Suite("Package topology")
struct PackageTopologyGuardTests {

    @Test func objcRuntimeToolboxTargetDependsOnItsMacroTargetOnly() throws {
        let manifest = try Self.dumpPackageManifest()

        let targets = try #require(manifest["targets"] as? [[String: Any]])
        let objcRuntimeToolboxTarget = try #require(
            targets.first { $0["name"] as? String == "ObjCRuntimeToolbox" }
        )
        let dependencies = try #require(objcRuntimeToolboxTarget["dependencies"] as? [[String: Any]])

        // Each dependency is a single-key object like
        // `{"byName": ["ObjCRuntimeToolboxMacros", null]}` (`"target"` and
        // `"product"` are the explicit spellings); the first array element is
        // always the dependency's name.
        let dependencyNames = try dependencies.map { dependency -> String in
            let payload = try #require(dependency.values.first as? [Any])
            return try #require(payload.first as? String)
        }

        #expect(dependencyNames == ["ObjCRuntimeToolboxMacros"])
    }

    private enum PackageTopologyGuardError: Error {
        case packageDirectoryNotFound
        case dumpPackageFailed(exitCode: Int32, standardError: String)
    }

    private static func packageDirectory() throws -> URL {
        var candidateDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while candidateDirectory.path != "/" {
            let manifestPath = candidateDirectory.appendingPathComponent("Package.swift").path
            if FileManager.default.fileExists(atPath: manifestPath) {
                return candidateDirectory
            }
            candidateDirectory.deleteLastPathComponent()
        }
        throw PackageTopologyGuardError.packageDirectoryNotFound
    }

    private static func dumpPackageManifest() throws -> [String: Any] {
        let dumpProcess = Process()
        dumpProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        dumpProcess.arguments = [
            "swift", "package", "dump-package",
            "--package-path", try packageDirectory().path,
            // An isolated scratch path, so evaluating the manifest never
            // contends with a concurrent build of the package itself.
            "--scratch-path", FileManager.default.temporaryDirectory
                .appendingPathComponent("ObjCRuntimeToolboxPackageTopologyGuard").path,
        ]

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        dumpProcess.standardOutput = standardOutputPipe
        dumpProcess.standardError = standardErrorPipe

        try dumpProcess.run()
        // Drain before waiting, or a dump larger than the pipe buffer
        // deadlocks the child.
        let standardOutputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        let standardErrorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        dumpProcess.waitUntilExit()

        guard dumpProcess.terminationStatus == 0 else {
            throw PackageTopologyGuardError.dumpPackageFailed(
                exitCode: dumpProcess.terminationStatus,
                standardError: String(decoding: standardErrorData, as: UTF8.self)
            )
        }

        let manifestObject = try JSONSerialization.jsonObject(with: standardOutputData)
        return try #require(manifestObject as? [String: Any])
    }
}

#endif
