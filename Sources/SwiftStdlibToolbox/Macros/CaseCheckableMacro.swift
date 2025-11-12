@attached(member, names: arbitrary)
public macro CaseCheckable(
    _ access: AccessLevel? = nil
) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "CaseCheckableMacro"
)
