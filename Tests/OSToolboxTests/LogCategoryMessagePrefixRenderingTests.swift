import Foundation
import OSLog
import Testing

@testable import OSToolbox

// Reads back what `#log(category:)` wrote, through `OSLogStore`, so what is
// checked is the text a reader of the log gets, rendered by `os` — rather than
// the expansion's source, which the snapshots in `OSToolboxMacroTests` cover.
//
// What this cannot check is redaction. An `xctest` process launched by
// `xcodebuild` logs `%{private}s` arguments in the clear: with the prefix
// deliberately interpolated as `.private`, the entry's format string read
// `%{private}srendered %{public}s` and its text still began with the name
// (measured). That the prefix is `privacy: .public` is pinned by the
// snapshots alone.

private let renderingSubsystem = "FrameworkToolbox.LogCategoryMessagePrefixRenderingTests"

extension LogCategory {
    fileprivate static let renderingWithPrefix = LogCategory("PrefixRendering", prefixesMessages: true)
    fileprivate static let renderingWithoutPrefix = LogCategory("PlainRendering")
}

@Loggable(.internal, subsystem: renderingSubsystem)
private struct MessagePrefixRenderer {
    /// `.default` rather than `.debug` or `.info`: the store only keeps those
    /// lower levels when the machine's log configuration asks for them.
    static func emitWithPrefix(_ marker: String) {
        #log(.default, category: .renderingWithPrefix, "rendered \(marker, privacy: .public)")
    }

    static func emitWithoutPrefix(_ marker: String) {
        #log(.default, category: .renderingWithoutPrefix, "rendered \(marker, privacy: .public)")
    }
}

extension ProcessWideSwitchTests {
    /// Nested here not because these flip a switch, but because a sibling suite
    /// that turns logging off for a moment would make them lose their message.
    @Suite
    struct LogCategoryMessagePrefixRenderingTests {

        @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
        @Test func aPrefixingCategoryRendersItsNameAheadOfTheMessage() async throws {
            let marker = makeMarker()

            MessagePrefixRenderer.emitWithPrefix(marker)

            let message = try await renderedMessage(inCategory: "PrefixRendering", containing: marker)
            #expect(message == "[PrefixRendering] rendered \(marker)")
        }

        @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
        @Test func aCategoryWithoutThePrefixRendersTheMessageUnchanged() async throws {
            let marker = makeMarker()

            MessagePrefixRenderer.emitWithoutPrefix(marker)

            let message = try await renderedMessage(inCategory: "PlainRendering", containing: marker)
            #expect(message == "rendered \(marker)")
        }
    }
}

/// A string no other run of these tests logs, so an entry left over from an
/// earlier run in the same process cannot satisfy the lookup.
private func makeMarker() -> String {
    String(UInt64.random(in: .min ... .max), radix: 36)
}

/// The composed text of the first entry this process logged to `category` that
/// contains `marker`, or `nil` if none shows up within thirty seconds — entries
/// reach the store asynchronously.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private func renderedMessage(inCategory category: String, containing marker: String) async throws -> String? {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let predicate = NSPredicate(format: "subsystem == %@ AND category == %@", renderingSubsystem, category)
    let deadline = Date().addingTimeInterval(30)
    repeat {
        for case let entry as OSLogEntryLog in try store.getEntries(matching: predicate)
        where entry.composedMessage.contains(marker) {
            return entry.composedMessage
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    } while Date() < deadline
    return nil
}
