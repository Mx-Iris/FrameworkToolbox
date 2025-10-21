import Foundation

public protocol SecureCodingCodable: NSObject, NSSecureCoding, Codable {}

extension SecureCodingCodable where Self: NSSecureCoding {
    public func encode(to encoder: Encoder) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}

extension Decodable where Self: NSObject, Self: NSSecureCoding {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)

        if let object = try NSKeyedUnarchiver.unarchivedObject(ofClass: Self.self, from: data) {
            self = object
        } else {
            throw SecureCodingCodableError.decodingFailed
        }
    }
}

private enum SecureCodingCodableError: Error {
    case encodingFailed
    case decodingFailed
}
