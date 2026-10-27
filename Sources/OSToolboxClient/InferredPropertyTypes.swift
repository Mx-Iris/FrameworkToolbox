import OSToolbox

// The lock macros without a type annotation. The property's type is inferred
// from its initial value and nothing the macros generate spells it out; the
// functions below pin that the inferred type is the one an annotation would
// have named. Every shape the storage can take is covered. It only has to
// compile.

final class InferredLockedValues: Sendable {
    @Mutex
    var count = 0

    @Mutex
    var names = [String]()

    @Mutex
    static var shared = 1.5
}

@available(SwiftStdlib 5.7, *)
final class InferredUnfairLockedValues: Sendable {
    @OSAllocatedUnfairLock
    var count = 0
}

func readInferredLockedValues(_ values: InferredLockedValues) -> (Int, [String], Double) {
    values.count += 1
    values.names.append("appended through _modify")
    return (values.count, values.names, InferredLockedValues.shared)
}

@available(SwiftStdlib 5.7, *)
func readInferredUnfairLockedValues(_ values: InferredUnfairLockedValues) -> Int {
    values.count += 1
    return values.count
}
