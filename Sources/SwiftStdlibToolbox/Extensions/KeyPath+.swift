import FrameworkToolbox

extension FrameworkToolbox where Base: AnyKeyPath {
    /// The name of the key path, if it's a @objc property, else the hash value.
    public var stringValue: String {
        if let string = base._kvcKeyPathString {
            return string
        }
        return String(base.hashValue)
    }
}
