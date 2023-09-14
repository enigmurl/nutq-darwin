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

fileprivate let takenSlave = "\"Resource in Use\""
fileprivate let slaveAboutToBeTaken = "\"Slave stolen\""
fileprivate let saveRate: TimeInterval = 10
fileprivate let gsyncInterval = 15 * TimeInterval.minute

protocol DatastoreManager: AnyObject {
    var schemes: [SchemeState] {get set}
}

class SystemManager: NSObject, URLSessionWebSocketDelegate {
    unowned var env: EnvState
    var lastSave = Date.distantPast
    var lastWrite: [SchemeStateMeta]? = nil
    var slaveSocket: URLSessionWebSocketTask? = nil
    
    init(env: EnvState) {
        self.env = env
    }
    
    func acquireSlave() async {
        guard let token = await updated_token(env: env), let url = URL(string: ws_url_base() + "/sync/slave/nutq") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        
        slaveSocket?.cancel()
        
        slaveSocket = session.webSocketTask(with: request)
        slaveSocket?.resume()
        
        DispatchQueue.main.async {
            self.env.slaveState = .loading
        }
        
        // receive initial data block, ensuring that the connection is not in conflict
        guard let res = try? await slaveSocket?.receive() else {
            self.slaveSocket = nil
            DispatchQueue.main.async {
                self.env.slaveState = .none
            }
            
            return
        }
        
        switch res {
        case .data(_):
            break
        case let .string(str):
            if str == takenSlave {
                break
            }
            else {
                let localCopy = self.load(from: "latest.json")
                
                // first iteration it will be null
                let holder = try? JSONDecoder().decode(SchemeHolder.self, from: str.data(using: .utf8)!)
                let current = holder ?? SchemeHolder(schemes: [])
                
                DispatchQueue.main.async {
                    self.lastWrite = self.createOverview(old: holder)
                 
                    // not even that inefficient since ids are checked first
                    for scheme in current.schemes {
                        if !(localCopy?.schemes ?? []).contains(where: scheme.deepEquals(_:)) {
                            scheme.remoteUpdated = true
                        }
                    }
                    
                    self.env.slaveState = .write
                    self.env.schemeHolder = current
                    self.saveLocal()
                }
                
                await self.listenForClose()
                
                return
            }
        @unknown default:
            break
        }
      
        DispatchQueue.main.async {
            self.slaveSocket = nil
            self.env.slaveState = .none
        }
    }
    
    private func listenForClose() async {
        while let message = try? await self.slaveSocket?.receive() {
            if case .string(let string) = message, string == slaveAboutToBeTaken {
                self.updateUpstream { 
                    self.slaveSocket?.cancel()
                    
                    DispatchQueue.main.async {
                        self.slaveSocket = nil
                        self.env.slaveState = .none
                    }
                }
            }
        }
    }
    
    func stealSlave() {
        self.env.slaveState = .loading
        
        Task.init {
            let _ = await auth_void_request(env: self.env, "/sync/steal/nutq", method: "DELETE")
            
            try await Task.sleep(for: .seconds(1)) // allow to finish sending changes
           
            // try acquiring (even if above fails), generally doesn't hurt
            await self.acquireSlave()
        }
    }
    
    func createOverview(old: SchemeHolder?) -> [SchemeStateMeta]? {
        guard let old = old else {
            return nil
        }
        
        return old.schemes.map { SchemeStateMeta(id: $0.id, items: $0.scheme_list.schemes.map {$0.id} ) }
    }
    
    enum UpdateType: String, Codable {
        case Create
        case Delete
    }
    
    struct Update: Encodable {
        let path: [AnyCodable]
        let delta_type: UpdateType
        let value: AnyCodable
    }
    
    func findUpdates() -> [Update] {
        guard let lastWrite = self.lastWrite else {
            return [self.env.schemeHolder.identityUpdate()]
        }
        
        return self.env.schemeHolder.updatesSince(lastWrite)
    }
    
    func updateUpstream(_ completion: @escaping () -> ()) {
        if self.env.slaveState != .write {
            return
        }
        
        Task.init {
            do {
                defer { 
                    DispatchQueue.main.async {
                        completion()
                    }
                }
                
                let updates = self.findUpdates()
                
                guard updates.count > 0 else {
                    self.slaveSocket?.sendPing { _ in }
                    return
                }
                
                self.saveLocal()
                
                let str = String(data: try! JSONEncoder().encode(updates), encoding: .utf8)!
                try await self.slaveSocket?.send(URLSessionWebSocketTask.Message.string(str))
               
                // recreate
                self.lastWrite = self.createOverview(old: self.env.schemeHolder)
            } catch { }
        }
    }
    
    func saveLocal() {
        guard let total = try? JSONEncoder().encode(self.env.schemeHolder) else {
            return
        }
       
        let dayOfWeek = Calendar.current.component(.weekday, from: .now) - 1
        
        self.save(total, to: "\(daysOfWeek[dayOfWeek]).json")
        self.save(total, to: "latest.json")
    }
    
    func save(_ data: Data, to file: String) {
        do {
            let supportDir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let jsonDir = supportDir.appendingPathComponent("backups/")
            try FileManager.default.createDirectory(at: jsonDir, withIntermediateDirectories: true, attributes: nil)
            
            try data.write(to: jsonDir.appendingPathComponent(file))
        } catch { }
    }
        
    func load(from file: String) -> SchemeHolder? {
        guard let url = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        
        return try? JSONDecoder().decode(SchemeHolder.self, from: Data(contentsOf: url.appending(components: "backups", file)))
    }
    
    func closeSlave() {
        Task.init {
            await auth_void_request(env: self.env, "/sync/steal/nutq", method: "DELETE")
        }
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
                        self.env.schemes[i].scheme_list.schemes.insert(SchemeItem(state: [0], text:  "ERR_{\(error.localizedDescription)}", repeats: .none, indentation: 0), at: 0)
                        print("Calendar events query error: \(error.localizedDescription)")
                        return
                    }
                    
                    self.env.schemes[i].scheme_list.schemes = []
                    
                    // Process the events returned in the response
                    if let events = (result as? GTLRCalendar_Events)?.items {
                        for (j, event) in events.enumerated() {
                            guard let start = event.start?.dateTime?.date, let end = event.end?.dateTime?.date else {
                                continue
                            }
                            
                            let finished = Date.now > end ? -1 : 0
                            let item = SchemeItem(state: [finished],
                                                  text: (event.summary ?? ""),
                                                  start: start,
                                                  end: end,
                                                  repeats: .none,
                                                  indentation: 0)
                            
                            self.env.schemes[i].scheme_list.schemes.insert(item, at: j)
                        }
                    }
                }
            }
        }
    }
    
    func loadFileSystem() {
        Task.init {
            await self.acquireSlave()
        }
    }
    
    func saveFileSystem(_ completion: @escaping () -> ()) {
        self.updateUpstream(completion)
    }
    
    func force(_ completion: @escaping () -> ()) {
        self.stateControl()
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

enum SlaveMode {
    case none
    case loading
    case write
}

public class EnvState: ObservableObject, DatastoreManager {
    var clock: AnyCancellable?
    
    @Published var stdTime: Date = .now
    @Published var scheme: UUID? = unionNullUUID
    @Published var esotericToken: EsotericUser? = nil {
        didSet {
            // save 
            UserDefaults.standard.setValue(try! JSONEncoder().encode(esotericToken), forKey: "esoteric_token")
        }
    }
    @Published var slaveState = SlaveMode.none
   
    @AppStorage("registeredDevice") var registered = false
    
    @Published var schemeHolder: SchemeHolder = SchemeHolder(schemes: [])
    var schemes: [SchemeState] {
        get { schemeHolder.schemes }
        set { schemeHolder.schemes = newValue }
    }
    
    var manager: SystemManager!
    weak var undoManager: UndoManager?
    
    init() {
        let raw = UserDefaults.standard.data(forKey: "esoteric_token")
        esotericToken = raw != nil ? try? JSONDecoder().decode(EsotericUser.self, from: raw!) : nil
        manager = SystemManager(env: self)
        clock = Timer.publish(every: saveRate, on: .main, in: .common)
            .autoconnect()
            .sink { val in
                self.stdTime = val // makes it so clock position is not out of data
                self.manager.stateControl()
                self.manager.saveFileSystem {
                    
                }
                self.manager.gsyncControl() // handled on next iteration ...
            }
        
        self.manager.loadFileSystem()
    }
    
    public func closeSlave() {
        self.manager.closeSlave()
    }
    
    public func stealSlave() {
        self.manager.stealSlave()
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
    @Published var schemeHolder: SchemeHolder = SchemeHolder(schemes: [])
    var schemes: [SchemeState] {
        get { schemeHolder.schemes }
        set { schemeHolder.schemes = newValue }
    }
    
    init(completion: @escaping (_ env: EnvMiniState) -> ()) {
        fatalError()
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
    
    case indent
    case deindent
    
    public var description: String {
        switch self {
        case .gotoUnion:
            return "Goto Union"
        case .prevScheme:
            return "Prev Scheme"
        case .indent:
            return "Indent"
        case .deindent:
            return "Deindent"
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
