import Foundation

/// A property-list value.
///
/// The store model uses it to carry content the library does not interpret (unknown keys,
/// option values it has no accessor for) through a read, modify and write cycle untouched.
public indirect enum PlistValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case array([PlistValue])
    case dictionary([String: PlistValue])

    /// Wraps a value produced by `PropertyListSerialization`.
    ///
    /// Returns `nil` when the value, or any element nested in it, is not a property-list type.
    public init?(any value: Any) {
        switch value {
        case let string as String:
            self = .string(string)
        case let date as Date:
            self = .date(date)
        case let data as Data:
            self = .data(data)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if ["d", "f"].contains(String(cString: number.objCType)) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let array as [Any]:
            var values: [PlistValue] = []
            values.reserveCapacity(array.count)
            for element in array {
                guard let wrapped = PlistValue(any: element) else { return nil }
                values.append(wrapped)
            }
            self = .array(values)
        case let dictionary as [String: Any]:
            var values: [String: PlistValue] = [:]
            for (key, element) in dictionary {
                guard let wrapped = PlistValue(any: element) else { return nil }
                values[key] = wrapped
            }
            self = .dictionary(values)
        default:
            return nil
        }
    }

    /// The value as the Foundation type `PropertyListSerialization` expects.
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .date(let value): return value
        case .data(let value): return value
        case .array(let values): return values.map(\.anyValue)
        case .dictionary(let values): return values.mapValues(\.anyValue)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var dictionaryValue: [String: PlistValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    public var arrayValue: [PlistValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> PlistValue? {
        dictionaryValue?[key]
    }
}

extension Dictionary where Key == String, Value == PlistValue {
    /// The dictionary as `[String: Any]`, for `PropertyListSerialization`.
    var anyValues: [String: Any] { mapValues(\.anyValue) }
}

extension Dictionary where Key == String, Value == Any {
    /// Wraps every entry as a `PlistValue`, dropping entries that are not property-list types.
    var plistValues: [String: PlistValue] {
        var out: [String: PlistValue] = [:]
        for (key, value) in self {
            if let wrapped = PlistValue(any: value) { out[key] = wrapped }
        }
        return out
    }
}
