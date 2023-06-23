//
//  SchemeUtil.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/17/23.
//

import Foundation
import SwiftUI

extension TimeInterval {
    static var day: TimeInterval {
        86400
    }
    
    static var week: TimeInterval {
        604800
    }
}

public let debugSchemes = [
    SchemeState(name: "Monocurl", colorIndex: 1, schemes: [
        SchemeItem(state: [1], text: "Example 1", start: nil, end: .now, blocks: 1, remainders: [0], modulus: 1, blockUnit: .day, children: [])
    ]),
    SchemeState(name: "UCSD", colorIndex: 2, schemes: [
        SchemeItem(state: [1], text: "Example 2", start: .now - 1000, end: .now + 100000, blocks: 1, remainders: [0], modulus: 1, blockUnit: .day, children: [])
    ]),
    SchemeState(name: "MaXentric", colorIndex: 3, schemes: [
        SchemeItem(state: [1], text: "Example 3", start: .now, end: .now + 1000, blocks: 1, remainders: [0], modulus: 1, blockUnit: .day, children: [])
    ]),
    SchemeState(name: "Nutq", colorIndex: 4, schemes: [
        SchemeItem(state: [1], text: "Example 4", start: nil, end: .now + 400000, blocks: 1, remainders: [0], modulus: 1, blockUnit: .day, children: [])
    ]),
    SchemeState(name: "Research", colorIndex: 5, schemes: [
        SchemeItem(state: [1], text: "Example 5", start: .now + 20000, end: nil, blocks: 1, remainders: [0], modulus: 1, blockUnit: .day, children: [])
    ]),
    SchemeState(name: "Ideas", colorIndex: 6, schemes: [
        SchemeItem(state: [1], text: "Example 6", start: .now, end: nil, blocks: 1, remainders: [0], modulus: 1, blockUnit: .day, children: [])
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
}

public struct SchemeItem: Identifiable {
    public var id = UUID()
    public var state: [Int] // 0 = not complete, -1 = finished. Open to intermediate states. Represents states of all events
    public var text: String
    
    public var start: Date?
    public var end: Date?
  
    public var blocks: Int
    public var remainders: [Int]
    public var modulus: Int
    public var blockUnit: TimeInterval
    
    public var children: [SchemeItem]?
    
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

public struct SchemeState: Identifiable {
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

fileprivate func convertSingularScheme(color: Int, path: [String], scheme: Binding<SchemeItem>, index: Int) -> SchemeSingularItem {
    let wrap = scheme.wrappedValue
    
    let mod = index % wrap.remainders.count
    let div = index / wrap.remainders.count
    
    let offset = Double(div * wrap.modulus + wrap.remainders[mod]) * wrap.blockUnit
    
    return SchemeSingularItem(
        id: SchemeSingularItem.IDPath(uuid: scheme.id, index: index),
        colorIndex: color,
        path: path,
        state: scheme.state[index],
        text: wrap.text,
        start: wrap.start == nil ? nil : wrap.start! + offset,
        end: wrap.end == nil ? nil : wrap.end! + offset
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
            
            for y in 0 ..< wrap.blocks * wrap.remainders.count {
                let base = convertSingularScheme(color: color, path: path, scheme: x, index: y)
                if base.start != nil && base.start! > start || base.end != nil && base.end! > start {
                    schemes.append(base)
                    break
                }
                else if base.state == 0 {
                    schemes.append(base)
                }
            }
            
            schemes += Binding(x.children)?.flattenToUpcomingSchemes(color: color, path: path + [wrap.text], start: start) ?? []
        }
        return schemes
    }
    
    func flattenFullSchemes(color: Int, path: [String]) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            for y in 0 ..< wrap.blocks * wrap.remainders.count {
                schemes.append(convertSingularScheme(color: color, path: path, scheme: x, index: y))
            }
            
            schemes += Binding(x.children)?.flattenFullSchemes(color: color, path: path + [wrap.text]) ?? []
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
            
            for y in 0 ..< wrap.blocks * wrap.remainders.count {
                let base = convertSingularScheme(color: color, path: path, scheme: x, index: y)
                if (base.start == nil || end == nil || base.start! < end!) &&
                    (base.end == nil || start == nil || base.end! > start!) {
                    schemes.append(base)
                }
            }
            
            schemes += Binding(x.children)?.flattenEventsInRange(color: color, path: path + [wrap.text], start: start, end: end, schemeTypes: schemeTypes) ?? []
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
