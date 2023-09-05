//
//  Environment.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import Foundation
import SwiftUI
import Combine
import BackgroundTasks
import GoogleSignIn
import GoogleAPIClientForREST_Calendar
import GTMSessionFetcherCore
import GTMSessionFetcherFull

let unionNullUUID = UUID(uuidString: "00000000-0000-0000-0000-ffffffffffff")!

fileprivate let gsyncInterval = 15 * TimeInterval.minute
fileprivate let gsyncHeader   = "[gc]"

protocol DatastoreManager: AnyObject {
    var schemes: [SchemeState] {get set}
}

#if os(macOS)
class Datastore: NSDocument {
    weak var env: DatastoreManager?
    var lastSaveCount: Int = 0
    var modCount: Int = 0
    
    init?(env: DatastoreManager) {
        self.env = env
    }
    
    override func data(ofType typeName: String) throws -> Data {
        NSLog("[Datastore] perform write")
        guard let env = self.env else {
            throw NSError(domain: "[Datastore]", code: 1)
        }
        return try JSONEncoder().encode(env.schemes)
    }
    
    override func read(from data: Data, ofType typeName: String) throws {
        NSLog("[Datastore] perform read")
        self.env?.schemes = try JSONDecoder().decode([SchemeState].self, from: data)
    }
    
    func save(_ completion: @escaping () -> ()) {
        guard self.lastSaveCount < self.modCount, let url = Self.url else {
            completion()
            return
        }
        
        self.lastSaveCount = self.modCount
        
        Task.init {
            try! await self.save(to: url, ofType: "nqd", for: .saveAsOperation)
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func load() async {
        guard let url = Self.url else {
            return
        }
        
        try? self.revert(toContentsOf: url, ofType: "nqd")
    }
}
#else
class Datastore: UIDocument {
    weak var env: DatastoreManager?
    var lastSaveCount: Int = 0
    var modCount: Int = 0
    
    init?(env: DatastoreManager) {
        guard let url = Self.url else {
            return nil
        }
        
        self.env = env
        super.init(fileURL: url)
    }
    
    override func contents(forType typeName: String) throws -> Any {
        NSLog("[Datastore] perform write")
        guard let env = self.env else {
            throw NSError(domain: "[Datastore]", code: 1)
        }
        return try JSONEncoder().encode(env.schemes)
    }
    
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else {
            throw NSError(domain: "[Datastore]", code: 1)
        }
        
        NSLog("[Datastore] perform read")
        self.env?.schemes = try JSONDecoder().decode([SchemeState].self, from: data)
    }
    
    func save(_ completion: @escaping () -> ()) {
        guard self.lastSaveCount < self.modCount, let url = Self.url else {
            return
        }
        
        self.lastSaveCount = self.modCount
        
        Task.init {
            await self.save(to: url, for: .forOverwriting)
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func load() async {
        await self.open()
    }
}
#endif

extension Datastore {
    class var url: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("main.nqd")
    }
}

class SystemManager {
    unowned var env: EnvState
    var lastSave = Date.distantPast
    
    init(env: EnvState) {
        self.env = env
    }
    
    func stateControl() {
        let binding = env.schemes.map { ObservedObject(initialValue: $0) }
        
        for item in binding.flattenIncomplete() {
            // autocomplete events
            if item.start != nil && item.end != nil && item.end! < .now {
                item.state = -1
            }
        }
    }
    
    func gsyncControl() {
        guard let authorizer = GIDSignIn.sharedInstance.currentUser?.fetcherAuthorizer, Date.now > lastSave + gsyncInterval else {
            return
        }
        
        lastSave = .now
        
        let service = GTLRCalendarService()
        service.authorizer = authorizer
        
        let query = GTLRCalendarQuery_EventsList.query(withCalendarId: "primary")
        query.timeMin = GTLRDateTime(date: Date.now.startOfDay())
        query.timeMax = GTLRDateTime(date: Date.now.startOfDay() + TimeInterval.week + TimeInterval.day)
        query.singleEvents = true
        query.orderBy = kGTLRCalendarOrderByStartTime
        
        // replace gsyncs...
        for (i, scheme) in self.env.schemes.enumerated() {
            if scheme.syncs_to_gsync {
                
                service.executeQuery(query) { (_, result, error) in
                    if let error = error {
                        // Handle the error
                        self.env.schemes[i].scheme_list.schemes.insert(SchemeItem(state: [0], text:  "ERR_{\(error.localizedDescription)} " + gsyncHeader, repeats: .none, indentation: 0), at: 0)
                        print("Calendar events query error: \(error.localizedDescription)")
                        return
                    }
                    
                    self.env.schemes[i].scheme_list.schemes = scheme.scheme_list.schemes.filter {!$0.text.hasSuffix(gsyncHeader)}
                    
                    // Process the events returned in the response
                    if let events = (result as? GTLRCalendar_Events)?.items {
                        for (j, event) in events.enumerated() {
                            guard let start = event.start?.dateTime?.date, let end = event.end?.dateTime?.date else {
                                continue
                            }
                            
                            let finished = Date.now > end ? -1 : 0
                            let item = SchemeItem(state: [finished],
                                                  text: (event.summary ?? "") + " " + gsyncHeader,
                                                  start: start,
                                                  end: end,
                                                  repeats: .none,
                                                  indentation: 0)
                            
                            self.env.schemes[i].scheme_list.schemes.insert(item, at: j)
                        }
                    }
                }
            
                break
            }
        }
        
    }
    
    func remindersControl() {
        
    }
    
    func loadFileSystem() {
        Task.init {
            await self.env.document?.load()
        }
    }
    
    func saveFileSystem(_ completion: @escaping () -> ()) {
        self.env.document?.save(completion)
    }
    
    func force(_ completion: @escaping () -> ()) {
        self.stateControl()
        self.remindersControl()
        self.saveFileSystem(completion)
    }
}

struct EsotericUser: Codable {
    let id: Int
    let username: String
    var access: String
    let refresh: String
    var access_exp: Int
    let refresh_exp: Int
}

public class EnvState: ObservableObject, DatastoreManager {
    var clock: AnyCancellable?
    
    @Published var stdTime: Date = .now
    @Published var scheme: UUID? = unionNullUUID
    @Published var esotericToken: EsotericUser? = nil {
        didSet {
            // save 
            UserDefaults().setValue(try! JSONEncoder().encode(esotericToken), forKey: "esoteric_token")
        }
    }
    
    /* doubly buffered */
    var document: Datastore!
    @Published var schemes: [SchemeState] = [] {
        didSet {
            document?.modCount += 1
        }
    }
    
    var manager: SystemManager!
    weak var undoManager: UndoManager?
    
    init() {
        let raw = UserDefaults().data(forKey: "esoteric_token")
        esotericToken = raw != nil ? try? JSONDecoder().decode(EsotericUser.self, from: raw!) : nil
        manager = SystemManager(env: self)
        document = Datastore(env: self)
        clock = Timer.publish(every: .minute, on: .main, in: .common)
            .autoconnect()
            .sink { val in
                self.stdTime = val // makes it so clock position is not out of data
                self.manager.stateControl()
                self.manager.saveFileSystem({})
                self.manager.gsyncControl() // handled on next iteration ...
            }
        
        self.manager.loadFileSystem()
    }
    
    public func startup() {
        GIDSignIn.sharedInstance.restorePreviousSignIn() { _, _ in
            self.stdTime = .now
        }
    }
    
    public func delete(uuid: UUID) {
        guard let index = self.schemes.firstIndex(where: {$0.id == uuid}) else {
            return
        }
        
        let state = self.schemes[index]
        self.schemes.remove(at: index)
        
        undoManager?.registerUndo(withTarget: self) {$0.insert(scheme: state, at: index)}
    }
    
    public func insert(scheme: SchemeState, at index: Int) {
        self.schemes.insert(scheme, at: index)
        
        undoManager?.registerUndo(withTarget: self) {$0.delete(uuid: scheme.id)}
    }
    
    // regular state is way too expensive
    public func refresh() {
        self.stdTime = .now
    }
    
    deinit {
        manager.force({})
    }
}

/* for widgets */
public class EnvMiniState: ObservableObject, DatastoreManager {
    @Published var schemes: [SchemeState] = []
    
    init(completion: @escaping (_ env: EnvMiniState) -> ()) {
        guard let document = Datastore(env: self) else {
            completion(self)
            return
        }
        
        Task.init {
            await document.load()
            await document.close()
            completion(self)
        }
    }
}

public enum MenuAction: CustomStringConvertible {
    case gotoUnion
    case nextScheme
    case prevScheme
    
    case toggle
    
    case toggleStartView
    case disableStart
    case toggleEndView
    case disableEnd
    case toggleBlockView
    case disableBlock
    
    public var description: String {
        switch self {
        case .gotoUnion:
            return "Goto Union"
        case .prevScheme:
            return "Prev Scheme"
        case .nextScheme:
            return "Next Scheme"
        case .toggle:
            return "Toggle Completion"
        case .toggleStartView:
            return "Toggle Start View"
        case .disableStart:
            return "Disable Start"
        case .toggleEndView:
            return "Toggle End View"
        case .disableEnd:
            return "Disable End"
        case .toggleBlockView:
            return "Toggle Block View"
        case .disableBlock:
            return "Disable Block"
        }
    }
}

// https://stackoverflow.com/a/62676412
public typealias Buffer = PassthroughSubject<MenuAction, Never>
public class MenuState: ObservableObject, Subject {
    public typealias ObjectWillChangePublisher = Buffer
    public typealias Output = Buffer.Output
    public typealias Failure = Buffer.Failure
    
    public let objectWillChange: ObjectWillChangePublisher
    public init(subject: ObjectWillChangePublisher = Buffer()) {
        objectWillChange = subject
    }
    
    public func send(subscription: Subscription) {
        objectWillChange.send(subscription: subscription)
    }
    
    public func send(_ value: Buffer.Output) {
        objectWillChange.send(value)
    }
    
    public func send(completion: Subscribers.Completion<Buffer.Failure>) {
        objectWillChange.send(completion: completion)
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Buffer.Failure == S.Failure, Buffer.Output == S.Input {
        objectWillChange.receive(subscriber: subscriber)
    }
}

public extension Binding<String> {
    init(digits: Binding<Int>, min: Int? = nil, max: Int? = nil) {
        self.init(get: {
            String(digits.wrappedValue)
        }, set: { str in
            let raw = Int(str.filter {$0.isNumber}) ?? 0
            digits.wrappedValue = Swift.max(Swift.min(raw, max ?? Int.max), min ?? Int.min)
        })
    }
}
