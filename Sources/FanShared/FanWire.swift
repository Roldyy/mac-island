import Foundation

public enum FanWireError: Error, Equatable {
    case payloadTooLarge
}

/// JSON in `Data` is the only payload type crossing XPC: no custom class is ever decoded by the
/// helper, so there is nothing for `NSSecureCoding` to get wrong. Size is capped before decoding.
public enum FanWire {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)   // throws on NaN / infinity (default strategy)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= FanHelperContract.maxPayloadBytes else { throw FanWireError.payloadTooLarge }
        return try JSONDecoder().decode(type, from: data)
    }
}
