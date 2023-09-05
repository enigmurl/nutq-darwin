//
//  SchemeUtil.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/17/23.
//

import Foundation
import SwiftUI
import Combine

func blankEditor(_ str: String, indentation: Int = 0) -> SchemeItem {
    return SchemeItem(state: [0], text: str, repeats: .none, indentation: indentation)
}

struct SchemeSingularItem: Identifiable {
    struct IDPath: Hashable, Encodable {
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
    
    var dateColor: Color {
        let time = self.start ?? self.end!
        // same day
        if time.dayDifference(with: .now) <= 0 {
            return Color(red: 0.75, green: 0.75, blue: 1)
        }
        else if time.dayDifference(with: .now) <= 1 {
            return Color(red: 0.9, green: 0.9, blue: 1)
        }
        else {
            return .white
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
        var block_unit: TimeInterval = .day
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
                    let offset = Double(i * block.modulus + r) * block.block_unit
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
            let offset = Double(block.remainders.first ?? 0) * block.block_unit
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
            let offset = Double((block.blocks - 1) * block.modulus + (block.remainders.last ?? 0)) * block.block_unit
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

public final class SchemeItem: ObservableObject, Codable, Hashable, Identifiable {
    public let id: UUID
    @Published public var state: [Int] // 0 = not complete, -1 = finished. Open to intermediate states. Represents states of all events
    @Published public var text: String
    
    @Published public var start: Date?
    @Published public var end: Date?
  
    @Published public var repeats: SchemeRepeat
    
    @Published public var indentation: Int
    
    public var scheme_type: SchemeType {
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
    
    enum CodingKeys: String, CodingKey {
        case id
        case state
        case text
        case start
        case end
        case repeats
        case indentation
    }
    
    init(id: UUID = UUID(), state: [Int], text: String, start: Date? = nil, end: Date? = nil, repeats: SchemeRepeat, indentation: Int) {
        self.id = id
        self.state = state
        self.text = text
        self.start = start
        self.end = end
        self.repeats = repeats
        self.indentation = indentation
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.state = try container.decode([Int].self, forKey: .state)
        self.text = try container.decode(String.self, forKey: .text)
        self.start = try container.decode(Optional<Date>.self, forKey: .start)
        self.end = try container.decode(Optional<Date>.self, forKey: .end)
        self.repeats = try container.decode(SchemeRepeat.self, forKey: .repeats)
        self.indentation = try container.decode(Int.self, forKey: .indentation)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(state, forKey: .state)
        try container.encode(text, forKey: .text)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(repeats, forKey: .repeats)
        try container.encode(indentation, forKey: .indentation)
    }
    
    public var complete: Bool {
        state.allSatisfy { $0 == -1 }
    }
    
    public var statePublisher: AnyPublisher<[Int], Never> {
        $state.eraseToAnyPublisher()
    }
    
    public static func == (lhs: SchemeItem, rhs: SchemeItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public final class SchemeItemList: ObservableObject, Codable, Hashable {
    var id: UUID!
    @Published var schemes: [SchemeItem]
    
    enum CodingKeys: String, CodingKey {
        case schemes
    }

    init(schemes: [SchemeItem]) {
        self.schemes = schemes
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemes = try container.decode([SchemeItem].self, forKey: .schemes)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemes, forKey: .schemes)
    }
    
    public static func == (lhs: SchemeItemList, rhs: SchemeItemList) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(schemes)
    }
}

public final class SchemeState: ObservableObject, Codable, Hashable, Identifiable {
    public let id: UUID
    
    @Published public var name: String
    @Published public var color_index: Int
    @Published public var syncs_to_gsync: Bool = false
    
    public var scheme_list: SchemeItemList
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color_index
        case syncs_to_gsync
        case scheme_list
    }
    
    init(id: UUID = UUID(), name: String, color_index: Int, syncs_to_gsync: Bool = false, scheme_list: SchemeItemList) {
        self.id = id
        self.name = name
        self.color_index = color_index
        self.syncs_to_gsync = syncs_to_gsync
        self.scheme_list = scheme_list
        self.scheme_list.id = id
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.color_index = try container.decode(Int.self, forKey: .color_index)
        self.syncs_to_gsync = try container.decode(Bool.self, forKey: .syncs_to_gsync)
        self.scheme_list = try container.decode(SchemeItemList.self, forKey: .scheme_list)
        self.scheme_list.id = id
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color_index, forKey: .color_index)
        try container.encode(syncs_to_gsync, forKey: .syncs_to_gsync)
        try container.encode(scheme_list, forKey: .scheme_list)
    }
    
    public static func == (lhs: SchemeState, rhs: SchemeState) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public final class SchemeType: OptionSet {
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
            if wrap.scheme_type == .procedure {
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
    
    func flattenIncomplete(color: Int, path: [String]) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(color: color, path: path, start: s, end: e, scheme: x, index: i)
                if base.state != -1 {
                    schemes.append(base)
                }
            }
        }
        return schemes
    }
    
    func flattenEventsInRange(color: Int, path: [String], start: Date?, end: Date?, schemeTypes: SchemeType) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            if !schemeTypes.contains(wrap.scheme_type) {
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

extension Array<ObservedObject<SchemeState>> {
    
    /* for a recurring event, does not have duplicates*/
    func flattenToUpcomingSchemes(start: Date) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenToUpcomingSchemes(color: x.wrappedValue.color_index, path: [x.wrappedValue.name], start: start))
        }
        return schemes
    }
    
    func flattenFullSchemes() -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenFullSchemes(color: x.wrappedValue.color_index, path: [x.wrappedValue.name]))
        }
        return schemes
    }
    
    func flattenIncomplete() -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenIncomplete(color: x.wrappedValue.color_index, path: [x.wrappedValue.name]))
        }
        return schemes
    }
    
    func flattenEventsInRange(start: Date?, end: Date?, schemeTypes: SchemeType) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenEventsInRange(color: x.wrappedValue.color_index, path: [x.wrappedValue.name], start: start, end: end, schemeTypes: schemeTypes))
        }
        return schemes
    }
}
