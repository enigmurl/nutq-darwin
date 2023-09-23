//
//  SchemeUtil.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/17/23.
//

import Foundation
import SwiftUI
import Combine

fileprivate let reminderOffset: TimeInterval = 0
fileprivate let eventOffset: TimeInterval = .minute * -10
fileprivate let assignmentOffset: TimeInterval = .hour * -2

fileprivate let eventEndDelay: TimeInterval = .hour
fileprivate let assignmentEndDelay: TimeInterval = 10 * .minute

func blankEditor(_ str: String, indentation: Int = 0) -> SchemeItem {
    return SchemeItem(state: [SchemeSingularState()], text: str, repeats: .None, indentation: indentation)
}

public struct SchemeSingularState: Codable, Hashable {
    var progress: Int = 0
    var delay: TimeInterval = 0
}

struct SchemeSingularItem: Identifiable {
    struct IDPath: Hashable, Encodable {
        public let uuid: UUID
        public let index: Int
    }
    
    public var id: Self.IDPath
    public let scheme_id: UUID
    public let colorIndex: Int
    public let path: [String]
    
    @Binding public var state: SchemeSingularState
    public var text: String
    
    public var start: Date?
    public var end: Date?
    
    public var notificationStart: Date
    public var notificationEnd: Date?
    
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
        if time < .now {
            return Color.red
        }
        else if time.dayDifference(with: .now) <= 0 {
            return Color(red: 0.75, green: 0.75, blue: 1)
        }
        else if time.dayDifference(with: .now) <= 1 {
            return Color(red: 0.9, green: 0.9, blue: 1)
        }
        else {
            return .primary
        }
    }
    
    var widgetDateColor: Color {
        let time = self.start ?? self.end!
        // same day
        if time < .now {
            return Color.red
        }
        else if time.dayDifference(with: .now) <= 0 {
            return Color(red: 0.5, green: 0.3, blue: 1)
        }
        else if time.dayDifference(with: .now) <= 1 {
            return Color(red: 0.5, green: 0.3, blue: 0.7)
        }
        else {
            return .primary
        }
    }
}

/* polymorphism at some point? */
public enum SchemeRepeat: Codable, Hashable, CustomStringConvertible {
    case None
    case Block(block: BlockRepeat)
    
    public struct BlockRepeat: Codable, Hashable {
        static let maxBlocks = 256
        
        var blocks: Int = 1
        var remainders: [Int] = [0]
        var modulus: Int = 7
        var block_unit: TimeInterval = .day
    }
    
    public var description: String {
        switch (self) {
        case .None:
            return "none"
        case .Block:
            return "block"
        }
    }
    
    public func events(start: Date?, end: Date?) -> [(start: Date?, end: Date?)] {
        switch(self) {
        case .None:
            return [(start, end)]
        case let .Block(block):
            let calendar = Calendar.current
            
            var ret: [(start: Date?, end: Date?)] = []
            for i in 0 ..< block.blocks {
                for r in block.remainders {
                    if block.block_unit == .day {
                        let offset = i * block.modulus + r
                        ret.append((start != nil ? calendar.date(byAdding: .day, value: offset, to: start!) : nil,
                                    end != nil ? calendar.date(byAdding: .day, value: offset, to: end!) : nil))
                    }
                    else {
                        fatalError()
                    }
                }
            }
    
            return ret
        }
    }
    
    public func lowerBound(start: Date?, end: Date?) -> Date? {
        switch(self) {
        case .None:
            return start ?? end
        case let .Block(block):
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
        case .None:
            return end ?? start
        case let .Block(block):
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
    
    @Published public var state: [SchemeSingularState] { // 0 = not complete, -1 = finished. Open to intermediate states. Represents states of all events
        didSet { if state != oldValue { dirty = true } }
    }
    
    @Published public var text: String {
        didSet { if text != oldValue { dirty = true } }
    }
    
    @Published public var start: Date? {
        didSet { if start != oldValue { dirty = true } }
    }
    
    @Published public var end: Date? {
        didSet { if end != oldValue { dirty = true } }
    }
    
    @Published public var repeats: SchemeRepeat {
        didSet { if repeats != oldValue { dirty = true } }
    }
    
    @Published public var indentation: Int {
        didSet { if indentation != oldValue { dirty = true } }
    }
    
    public var dirty = true
    
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
    
    init(id: UUID = UUID(), state: [SchemeSingularState], text: String, start: Date? = nil, end: Date? = nil, repeats: SchemeRepeat, indentation: Int) {
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
        self.state = try container.decode([SchemeSingularState].self, forKey: .state)
        self.text = try container.decode(String.self, forKey: .text)
        self.start = try container.decode(Optional<Date>.self, forKey: .start)
        self.end = try container.decode(Optional<Date>.self, forKey: .end)
        self.repeats = try container.decode(SchemeRepeat.self, forKey: .repeats)
        self.indentation = try container.decode(Int.self, forKey: .indentation)
        
        self.dirty = false
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
        state.allSatisfy { $0.progress == -1 }
    }
    
    public var mergedStatePublisher: AnyPublisher<Void, Never> {
        return Publishers.Merge4(
            $state.map { _ in }.eraseToAnyPublisher(),
            $start.map { _ in }.eraseToAnyPublisher(),
            $end.map { _ in }.eraseToAnyPublisher(),
            $repeats.map { _ in }.eraseToAnyPublisher()
        ).eraseToAnyPublisher()
    }
    
    public static func == (lhs: SchemeItem, rhs: SchemeItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public func deepEquals(_ other: SchemeItem) -> Bool {
        return self.id == other.id && self.state == other.state && self.text == other.text && self.start == other.start && self.end == other.end && self.repeats == other.repeats && self.indentation == other.indentation
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
    
    @Published public var name: String {
        didSet { if name != oldValue { dirty = true } }
    }
    
    @Published public var color_index: Int {
        didSet { if color_index != oldValue { dirty = true } }
    }
    
    @Published public var syncs_to_gsync: Bool = false {
        didSet { if syncs_to_gsync != oldValue { dirty = true } }
    }
    
    public var scheme_list: SchemeItemList
   
    #warning ("TODO not perfect since it resets after we shutdown")
    public var remoteUpdated: Bool = false
    public var dirty: Bool = true
    
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
        
        self.dirty = false
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
    
    public func deepEquals(_ other: SchemeState) -> Bool {
        return self.id == other.id && name == other.name && color_index == other.color_index && syncs_to_gsync == other.syncs_to_gsync && scheme_list.schemes.count == other.scheme_list.schemes.count &&  zip(scheme_list.schemes, other.scheme_list.schemes).allSatisfy { $0.0.deepEquals($0.1) }
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

public struct SchemeHolder: Codable {
    public var schemes: [SchemeState]
    
    func identityDelete() -> SystemManager.Update {
        return SystemManager.Update(path: [AnyCodable(value: "schemes")], delta_type: .Delete, value: AnyCodable(value: 0))
    }
    
    func identityUpdate() -> SystemManager.Update {
        let data = try! JSONEncoder().encode(self.schemes)
        let obj = try! JSONSerialization.jsonObject(with: data)
        return SystemManager.Update(path: [AnyCodable(value: "schemes")], delta_type: .Create, value: AnyCodable(value: obj))
    }
    
    func updatesSince(_ metas: [SchemeStateMeta]) -> [SystemManager.Update] {
        // if any schemes were moved around (rare), rewrite entirely
        
        var deleteSchemes: [SystemManager.Update] = []
        var createSchemes: [Int] = []
        var deleteItems: [SystemManager.Update] = []
        var createItems: [SystemManager.Update] = []
        
        // deleted schemes
        var old_id_map = [UUID: Int](uniqueKeysWithValues: metas.enumerated().map { ($0.element.id, $0.offset) })
       
        // schemes plus
        for (i, scheme) in schemes.enumerated() {
            if scheme.dirty {
                createSchemes.append(i)
                
                scheme.dirty = false
            }
            else {
                // scheme items plus or minus
                guard let index = old_id_map[scheme.id] else {
                    // should never fail...
                    continue
                }
                
                var inner_map = [UUID: Int](uniqueKeysWithValues: metas[index].items.enumerated()
                    .map { ($0.element, $0.offset) }
                )
                
                for (j, item) in scheme.scheme_list.schemes.enumerated() {
                    if item.dirty {
                        let obj = try! JSONSerialization.jsonObject(with: try! JSONEncoder().encode(item))

                        createItems.append (
                            SystemManager.Update(
                                path: [AnyCodable(value: "schemes"), AnyCodable(value: i), AnyCodable(value: "scheme_list"), AnyCodable(value: "schemes"), AnyCodable(value: j)],
                                delta_type: .Create,
                                value: AnyCodable(value: obj)
                            )
                        )
                        
                        item.dirty = false
                    }
                    else {
                        inner_map.removeValue(forKey: item.id)
                    }
                }
                
                deleteItems += inner_map.map { $0.value }.sorted().map {
                    SystemManager.Update(
                        path: [AnyCodable(value: "schemes"), AnyCodable(value: i), AnyCodable(value: "scheme_list"),  AnyCodable(value: "schemes"),  AnyCodable(value: $0)],
                        delta_type: .Delete,
                        value: AnyCodable(value: 0)
                    )
                }.reversed()
                
                old_id_map.removeValue(forKey: scheme.id)
            }
        }
        
        // deleted schemes
        deleteSchemes = old_id_map.map { $0.value }.sorted().map {
            SystemManager.Update(
                path: [AnyCodable(value: "schemes"), AnyCodable(value: $0)],
                delta_type: .Delete,
                value: AnyCodable(value: 0)
            )
        }.reversed()
        
        
        var checkSum = metas.map { $0.id }
        for update in deleteSchemes {
            guard let last = update.path.last?.value as? Int else {
                continue
            }
            
            checkSum.remove(at: last)
        }
        
        for ind in createSchemes {
            checkSum.append(schemes[ind].id)
        }
        
        // schemes were moved around (can't happen with items)
        // rare event, so a full refresh is ok
        if checkSum != schemes.map({ $0.id }) {
            return [self.identityDelete(), self.identityUpdate()]
        }
        
        // reverse deletes so indices are in correct order
        return deleteSchemes + createSchemes.map {
            let obj = try! JSONSerialization.jsonObject(with: try! JSONEncoder().encode(schemes[$0]))
            
            return SystemManager.Update(
                path: [AnyCodable(value: "schemes"), AnyCodable(value: $0)],
                delta_type: .Create,
                value: AnyCodable(value: obj)
            )
        } + deleteItems + createItems
    }
}

public struct SchemeStateMeta {
    let id: UUID
    let items: [UUID]
}

func singularSchemeNotificationDelay(scheme: SchemeItem, index: Int) -> (TimeInterval, TimeInterval) {
    let start_delay: TimeInterval
    var end_delay: TimeInterval = 0
    
    switch scheme.scheme_type {
    case .reminder:
        start_delay = reminderOffset
    case .assignment:
        start_delay = assignmentOffset
        end_delay = assignmentEndDelay
    case .event:
        start_delay = eventOffset
        end_delay = eventEndDelay
    default:
        start_delay = 0
    }
    
    return (start_delay + scheme.state[index].delay, end_delay)
}

fileprivate func convertSingularScheme(scheme_id: UUID, color: Int, path: [String], start: Date?, end: Date?, scheme: Binding<SchemeItem>, index: Int) -> SchemeSingularItem {
    let wrap = scheme.wrappedValue
  
    let (start_delay, end_delay) = singularSchemeNotificationDelay(scheme: wrap, index: index)
    
    return SchemeSingularItem(
        id: SchemeSingularItem.IDPath(uuid: scheme.id, index: index),
        scheme_id: scheme_id,
        colorIndex: color,
        path: path,
        state: scheme.state[index],
        text: wrap.text,
        start: start,
        end: end,
        notificationStart: Calendar.current.date(bySetting: .second, value: 0, of: (start ?? end ?? .now) + start_delay)!,
        notificationEnd: wrap.state[index].delay == 0 ? end?.addingTimeInterval(end_delay) : nil
    )
}

#warning("TODO specialized flattens can be made more efficient (bisect)")
extension Binding<Array<SchemeItem>> {
    /* if it's unfinished, or if it's in future and first event*/
    func flattenToUpcomingSchemes(scheme_id: UUID, color: Int, path: [String], start: Date) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            if wrap.scheme_type == .procedure {
                continue
            }
            
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(scheme_id: scheme_id, color: color, path: path, start: s, end: e, scheme: x, index: i)
                if base.start != nil && base.start! > start || base.end != nil && base.end! > start {
                    schemes.append(base)
                    break
                }
                else if base.state.progress != -1 {
                    schemes.append(base)
                }
            }
        }
        return schemes
    }
    
    func flattenFullSchemes(scheme_id: UUID, color: Int, path: [String]) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(scheme_id: scheme_id, color: color, path: path, start: s, end: e, scheme: x, index: i)
                schemes.append(base)
            }
        }
        return schemes
    }
    
    func flattenIncomplete(scheme_id: UUID, color: Int, path: [String]) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(scheme_id: scheme_id, color: color, path: path, start: s, end: e, scheme: x, index: i)
                if base.state.progress != -1 {
                    schemes.append(base)
                }
            }
        }
        return schemes
    }
    
    func flattenEventsInRange(scheme_id: UUID, color: Int, path: [String], start: Date?, end: Date?, schemeTypes: SchemeType) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            let wrap = x.wrappedValue
            if !schemeTypes.contains(wrap.scheme_type) {
                continue
            }
            
            for (i, (s, e)) in wrap.repeats.events(start: wrap.start, end: wrap.end).enumerated() {
                let base = convertSingularScheme(scheme_id: scheme_id, color: color, path: path, start: s, end: e, scheme: x, index: i)
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
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenToUpcomingSchemes(scheme_id: x.wrappedValue.id, color: x.wrappedValue.color_index, path: [x.wrappedValue.name], start: start))
        }
        return schemes
    }
    
    func flattenFullSchemes() -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenFullSchemes(scheme_id: x.wrappedValue.id, color: x.wrappedValue.color_index, path: [x.wrappedValue.name]))
        }
        return schemes
    }
    
    func flattenIncomplete() -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenIncomplete(scheme_id: x.wrappedValue.id, color: x.wrappedValue.color_index, path: [x.wrappedValue.name]))
        }
        return schemes
    }
    
    func flattenEventsInRange(start: Date?, end: Date?, schemeTypes: SchemeType) -> [SchemeSingularItem] {
        var schemes: [SchemeSingularItem] = []
        for x in self {
            schemes.append(contentsOf: x.projectedValue.scheme_list.schemes.flattenEventsInRange(scheme_id: x.wrappedValue.id, color: x.wrappedValue.color_index, path: [x.wrappedValue.name], start: start, end: end, schemeTypes: schemeTypes))
        }
        return schemes
    }
}
