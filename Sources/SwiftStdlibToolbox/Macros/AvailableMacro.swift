/// A property macro that creates `Any?` storage and a lazy getter for
/// availability-gated properties whose backing storage cannot mention the
/// gated type directly.
@attached(peer, names: suffixed(Storage))
@attached(accessor)
public macro AvailableNonMutating(_ defaultValue: Any) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AvailableNonMutatingMacro"
)

/// A property macro that creates `Any?` storage, a lazy getter, and a setter for
/// availability-gated properties whose backing storage cannot mention the
/// gated type directly.
@attached(peer, names: suffixed(Storage))
@attached(accessor)
public macro AvailableMutating(_ defaultValue: Any) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AvailableMutatingMacro"
)
