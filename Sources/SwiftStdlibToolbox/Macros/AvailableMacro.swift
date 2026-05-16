/// A property macro that creates type-erased storage and a lazy getter for
/// availability-gated properties whose backing storage cannot mention the
/// gated type directly. The default value can be supplied as a macro argument
/// or as the property's initializer expression.
///
/// Pass `isSendable: true` when the property's type conforms to `Sendable` to
/// use `(any Sendable)?` storage; otherwise `Any?` storage is generated. In
/// both cases the storage is marked `nonisolated(unsafe)` so the macro can be
/// used inside `Sendable`-conforming types.
@attached(peer, names: suffixed(Storage))
@attached(accessor)
public macro AvailableNonMutating(_ defaultValue: Any? = nil, isSendable: Bool = false) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AvailableNonMutatingMacro"
)

/// A property macro that creates type-erased storage, a lazy getter, and a setter
/// for availability-gated properties whose backing storage cannot mention the
/// gated type directly. The default value can be supplied as a macro argument
/// or as the property's initializer expression.
///
/// Pass `isSendable: true` when the property's type conforms to `Sendable` to
/// use `(any Sendable)?` storage; otherwise `Any?` storage is generated. In
/// both cases the storage is marked `nonisolated(unsafe)` so the macro can be
/// used inside `Sendable`-conforming types.
@attached(peer, names: suffixed(Storage))
@attached(accessor)
public macro AvailableMutating(_ defaultValue: Any? = nil, isSendable: Bool = false) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "AvailableMutatingMacro"
)
