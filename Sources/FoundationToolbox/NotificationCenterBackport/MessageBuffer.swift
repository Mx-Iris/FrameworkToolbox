import Foundation

extension NotificationCenter.Backport {
    /// First-in, first-out storage for the messages an iterator has received but
    /// not handed out yet.
    ///
    /// Foundation's iterator keeps these in swift-collections' `Deque`, which this
    /// package does not depend on. Only four operations are needed — append at
    /// the back, remove from the front, count, and empty the whole buffer — so
    /// this is an array plus the index of its first live element, with the
    /// consumed prefix discarded once it is at least as long as what remains.
    /// That keeps every operation amortized O(1), as `Deque` is. An array alone
    /// would make each removal from the front O(n) in the buffer size, and the
    /// buffer size is the caller's to choose.
    struct MessageBuffer<Element> {
        private var storage: [Element?] = []
        private var firstElementIndex = 0

        init(minimumCapacity: Int) {
            storage.reserveCapacity(minimumCapacity)
        }

        var count: Int {
            storage.count - firstElementIndex
        }

        var isEmpty: Bool {
            count == 0
        }

        mutating func append(_ element: Element) {
            storage.append(element)
        }

        @discardableResult
        mutating func removeFirst() -> Element {
            precondition(!isEmpty, "Can't remove first element from an empty MessageBuffer")
            let element = storage[firstElementIndex].take()!
            firstElementIndex += 1
            if firstElementIndex * 2 >= storage.count {
                storage.removeFirst(firstElementIndex)
                firstElementIndex = 0
            }
            return element
        }

        mutating func removeAll(keepingCapacity keepCapacity: Bool) {
            storage.removeAll(keepingCapacity: keepCapacity)
            firstElementIndex = 0
        }
    }
}
