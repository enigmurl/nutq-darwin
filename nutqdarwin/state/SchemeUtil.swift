//
//  SchemeUtil.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/17/23.
//

import Foundation
import SwiftUI

extension TimeInterval {
    static var minute: TimeInterval {
        60
    }
    
    static var hour: TimeInterval {
        3600
    }
    
    static var day: TimeInterval {
        86400
    }
    
    static var week: TimeInterval {
        604800
    }
}

public let debugSchemes = [
    SchemeState(name: "Monocurl", colorIndex: 1, schemes: [
        SchemeItem(state: [1], text: "Example 1", start: .now + 1000, end: .now + 10000, repeats: .none, indentation: 0)
    ]),
    SchemeState(name: "UCSD", colorIndex: 2, schemes: [
        SchemeItem(state: [Int](repeating: 1, count: 20000), text: "Example 2", start: Date(timeInterval: 1200, since: Date.now - Date.now.timeIntervalSinceReferenceDate), end: Date(timeInterval: 4800, since: Date.now - Date.now.timeIntervalSinceReferenceDate), repeats: SchemeRepeat.block(block: SchemeRepeat.Block(blocks: 10000, remainders: [0, 1], modulus: 7, blockUnit: .day)), indentation: 0),
        SchemeItem(state: [1], text: "Example 3", start: nil, end: .now.startOfDay() + 9000, repeats: .none, indentation: 0)
    ]),
    SchemeState(name: "MaXentric", colorIndex: 3, schemes: [
        SchemeItem(state: [1], text: "Example 3", start: nil, end: .now.startOfDay() + 9000, repeats: .none, indentation: 0)
    ]),
    SchemeState(name: "Nutq", colorIndex: 4, schemes: [
        SchemeItem(state: [1], text: "Example 4", start: nil, end: .now.startOfDay() + 3000, repeats: .none, indentation: 0)
    ]),
    SchemeState(name: "Research", colorIndex: 5, schemes: [
        SchemeItem(state: [1], text: "Example 5", start: .now + 86400 * 3, end: nil, repeats: .none, indentation: 0)
    ]),
    SchemeState(name: "Ideas", colorIndex: 6, schemes: [
        SchemeItem(state: [1], text: "Example 6", start: nil, end: .now + 86400 * 2, repeats: .none, indentation: 0)
    ]),
]

struct SchemeSingularItem: Identifiable {
    struct IDPath: Hashable {
        public let uuid: UUID
        public let index: Int
    }
    
    public var id: Self.IDPath
    public let colorIndex: Int
    public let path: [String]
    
    @Binding public var state: Int
    public var text: String
    
    public var start: Date?
    public var end: Date?
    
    public var schemeType: SchemeType {
        if (start != nil && end != nil) {
            return .event
        }
        else if (end != nil) {
            return .assignment
        }
        else if (start != nil) {
            return .reminder
        }
        else {
            return .procedure
        }
    }
}

/* polymorphism at some point? */
public enum SchemeRepeat: Codable, Hashable, CustomStringConvertible {
    case none
    case block(block: Block)
    
    public struct Block: Codable, Hashable {
        static let maxBlocks = 256
        
        var blocks: Int = 1
        var remainders: [Int] = [0]
        var modulus: Int = 7
        var blockUnit: TimeInterval = .day
    }
    
    public var description: String {
        switch (self) {
        case .none:
            return "none"
        case .block:
            return "block"
        }
    }
    
    public func events(start: Date?, end: Date?) -> [(start: Date?, end: Date?)] {
        switch(self) {
        case .none:
            return [(start, end)]
        case let .block(block):
            var ret: [(start: Date?, end: Date?)] = []
            for i in 0 ..< block.blocks {
                for r in block.remainders {
                    let offset = Double(i * block.modulus + r) * block.blockUnit
                    ret.append((start != nil ? start! + offset : nil,
                                end != nil ? end! + offset : nil))
                }
            }
    
            return ret
        }
    }
    
    public func lowerBound(start: Date?, end: Date?) -> Date? {
        switch(self) {
        case .none:
            return start ?? end
        case let .block(block):
            let offset = Double(block.remainders.first ?? 0) * block.blockUnit
            if start != nil {
                return start! + offset
            }
            if end != nil {
                return end! + offset
            }
            return nil
        }
    }
    
    public func upperBound(start: Date?, end: Date?) -> Date? {
        switch(self) {
        case .none:
            return end ?? start
        case let .block(block):
            let offset = Double((block.blocks - 1) * block.modulus + (block.remainders.last ?? 0)) * block.blockUnit
            if end != nil {
                return end! + offset
            }
            if start != nil {
                return start! + offset
            }
  
            return nil
        }
    }
}

public struct SchemeItem: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var state: [Int] // 0 = not complete, -1 = finished. Open to intermediate states. Represents states of all events
    public var text: String
    
    public var start: Date?
    public var end: Date?
  
    public var repeats: SchemeRepeat
    
    public var indentation: Int
    
    public var schemeType: SchemeType {
        if (start != nil && end != nil) {
            return .event
        }
        else if (end != nil) {
            return .assignment
        }
        else if (start != nil) {
            return .reminder
        }
        else {
            return .procedure
        }
    }
}

public struct SchemeState: Codable, Hashable, Identifiable {
    public var id = UUID()
    
    public var name: String
    public var colorIndex: Int
    public var email: String?
    
    public var schemes: [SchemeItem]
}

public struct SchemeType: OptionSet {
    public let rawValue: UInt16
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    static let reminder = SchemeType(rawValue: 0x1)
    static let assignment = SchemeType(rawValue: 0x2)
    static let procedure = SchemeType(rawValue: 0x4)
    static let event = SchemeType(rawValue: 0x8)
}

fileprivate func convertSingularScheme(color: Int, path: [String], start: Date?, end: Date?, scheme: Binding<SchemeItem>, index: Int) -> SchemeSingularItem {
    let wrap = scheme.wrappedValue
    
    return SchemeSingularItem(
        id: SchemeSingularItem.IDPath(uuid: scheme.id, index: index),
        colorIndex: color,
        path: path,
        state: scheme.state[index],
        text: wrap.text,
        start: start,
        end: end
    )
}

#warning("TODO specialized flattens can be made more efficient (bisect)")
extension Binding<Array<SchemeItem>> {
    /* if it's unfinished, or if it's in future and first event*/
    func flattenToUpcomingSchemes(color: Int, path: [String], start: Date) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            if wrap.schemeType == .procedure {
                continue
            }
            
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(color: color, path: path, start: s, end: e, scheme: x, index: i)
                if base.start != nil && base.start! > start || base.end != nil && base.end! > start {
                    schemes.append(base)
                    break
                }
                else if base.state == 0 {
                    schemes.append(base)
                }
            }
        }
        return schemes
    }
    
    func flattenFullSchemes(color: Int, path: [String]) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(color: color, path: path, start: s, end: e, scheme: x, index: i)
                schemes.append(base)
            }
        }
        return schemes
    }
    
    func flattenEventsInRange(color: Int, path: [String], start: Date?, end: Date?, schemeTypes: SchemeType) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            if !schemeTypes.contains(wrap.schemeType) {
                continue
            }
            
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(color: color, path: path, start: s, end: e, scheme: x, index: i)
                if (base.start == nil || end == nil || base.start! < end!) &&
                    (base.end == nil || start == nil || base.end! > start!) {
                    schemes.append(base)
                }
            }
        }
        
        return schemes
    }
}

extension Array<Binding<SchemeState>> {
    /* for a recurring event, does not have duplicates*/
    func flattenToUpcomingSchemes(start: Date) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.schemes.flattenToUpcomingSchemes(color: x.wrappedValue.colorIndex, path: [x.wrappedValue.name], start: start))
        }
        return schemes
    }
    
    func flattenFullSchemes() -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.schemes.flattenFullSchemes(color: x.wrappedValue.colorIndex, path: [x.wrappedValue.name]))
        }
        return schemes
    }
    
    func flattenEventsInRange(start: Date?, end: Date?, schemeTypes: SchemeType) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.schemes.flattenEventsInRange(color: x.wrappedValue.colorIndex, path: [x.wrappedValue.name], start: start, end: end, schemeTypes: schemeTypes))
        }
        return schemes
    }
}
