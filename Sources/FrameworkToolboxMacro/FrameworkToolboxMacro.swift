import Foundation

@attached(member, names: arbitrary)
public macro FrameworkToolboxExtension() =
    #externalMacro(module: "FrameworkToolboxMacroPlugins", type: "FrameworkToolboxCompatibleMacro")
