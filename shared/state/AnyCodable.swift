//
//  AnyCodable.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 9/11/23.
//

import Foundation

// https://stackoverflow.com/a/48387516
struct AnyCodable: Encodable {
    var value: Any
    
    struct CodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
        init?(stringValue: String) { self.stringValue = stringValue }
    }
    
    init(value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        if let array = value as? [Any] {
            var container = encoder.unkeyedContainer()
            for value in array {
                let decodable = AnyCodable(value: value)
                try container.encode(decodable)
            }
        } else if let dictionary = value as? [String: Any] {
            var container = encoder.container(keyedBy: CodingKeys.self)
            for (key, value) in dictionary {
                let codingKey = CodingKeys(stringValue: key)!
                let decodable = AnyCodable(value: value)
                try container.encode(decodable, forKey: codingKey)
            }
        } else {
            var container = encoder.singleValueContainer()
            if let num = value as? NSNumber {
                switch CFGetTypeID(num as CFTypeRef) {
                case CFBooleanGetTypeID():
                    try container.encode(num as! Bool)
                case CFNumberGetTypeID():
                    switch CFNumberGetType(num as CFNumber) {
                    case .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type:
                        try container.encode(num as! Int)
                    case .doubleType, .floatType, .float32Type, .float64Type:
                        try container.encode(num as! Double)
                    default:
                        try container.encode(num as! Int)
                    }
                default:
                    try container.encode(num as! Int)
                }
            } else if let stringVal = value as? String {
                try container.encode(stringVal)
            } else if let _ = value as? NSNull {
                try container.encodeNil()
            } else {
                throw EncodingError.invalidValue(value, EncodingError.Context.init(codingPath: [], debugDescription: "The value is not encodable"))
            }
        }
    }
}
