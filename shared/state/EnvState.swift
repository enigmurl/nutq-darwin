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
import UserNotifications

let unionNullUUID = UUID(uuidString: "00000000-0000-0000-0000-ffffffffffff")!

fileprivate let takenSlave = "\"Resource in Use\""
fileprivate let slaveAboutToBeTaken = "\"Slave stolen\""
fileprivate let saveRate: TimeInterval = 7
fileprivate let gsyncInterval = 30 * TimeInterval.minute

protocol DatastoreManager: AnyObject {
    var esotericToken: EsotericUser? { get set }
    var schemes: [SchemeState] { get set }
    var slaveState: SlaveMode { get set }
    var schemeHolder: SchemeHolder { get set }
    var manager: SystemManager! { get set }
}

#if os(macOS)
let appGroup = "T35KD9JHQ6.group.com.enigmadux.nutqdarwin"
#else
let appGroup = "group.com.enigmadux.nutqdarwin"
#endif

fileprivate func save_scheme(_ data: Data, to file: String) {
    do {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return
        }
        
        let supportDir = sharedContainerURL.appending(component: "Library/Application Support", directoryHint: .isDirectory)
        let jsonDir = supportDir.appending(component: "backups/", directoryHint: .isDirectory)
        
        try FileManager.default.createDirectory(at: jsonDir, withIntermediateDirectories: true, attributes: nil)
        
        try data.write(to: jsonDir.appendingPathComponent(file))
    } catch let err { print("ERROR", err) }
}
    
fileprivate func load_scheme(from file: String) -> SchemeHolder? {
    guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
        return nil
    }
    
    let supportDir = sharedContainerURL.appending(component: "Library/Application Support", directoryHint: .isDirectory)
    let jsonDir = supportDir.appending(component: "backups/", directoryHint: .isDirectory)
    
    return try? JSONDecoder().decode(SchemeHolder.self, from: Data(contentsOf: jsonDir.appending(path: file, directoryHint: .notDirectory)))
}

class SystemManager: NSObject, URLSessionWebSocketDelegate {
    unowned var env: DatastoreManager
    var lastSave = Date.distantPast
    var lastWrite: [SchemeStateMeta]? = nil
    var slaveSocket: URLSessionWebSocketTask? = nil
    
    init(env: DatastoreManager) {
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
                
                // first iteration it will be null
                DispatchQueue.main.async {
                    let localCopy = load_scheme(from: "latest.json")

                    let holder = try? JSONDecoder().decode(SchemeHolder.self, from: str.data(using: .utf8)!)
                    let current = holder ?? SchemeHolder(schemes: [])
                    
                    self.lastWrite = self.createOverview(old: holder)
                 
                    // not even that inefficient since ids are checked first
                    for scheme in current.schemes {
                        if !(localCopy?.schemes ?? []).contains(where: scheme.deepEquals(_:)) {
                            scheme.remoteUpdated = !scheme.syncs_to_gsync
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
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.slaveSocket = nil
            self.env.slaveState = .none
        }
    }
    
    private func listenForClose() async {
        while let message = try? await self.slaveSocket?.receive() {
            if case .string(let string) = message, string == slaveAboutToBeTaken {
                await self.updateUpstream {
                    self.slaveSocket?.cancel()
                }
            }
        }
        
        DispatchQueue.main.async {
            self.slaveSocket = nil
            self.env.slaveState = .none
        }
    }
    
    func stealSlave() {
        guard self.env.slaveState == .none else {
            return
        }
        
        self.env.slaveState = .loading

        Task.init {
            let _ = await auth_void_request(env: self.env, "/sync/steal/nutq", method: "DELETE")
            
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
    
    @MainActor
    func updateUpstream(_ completion: @escaping () -> ()) {
        if self.env.slaveState != .write {
            completion()
            return
        }
        
        let updates = self.findUpdates()
        let overview = self.createOverview(old: self.env.schemeHolder)
        self.saveLocal()

        Task.init {
            do {
                defer { 
                    DispatchQueue.main.async {
                        completion()
                    }
                }
               
                guard updates.count > 0 else {
                    slaveSocket?.sendPing { _ in }
                    return
                }
                
                let str = String(data: try! JSONEncoder().encode(updates), encoding: .utf8)!
                try await self.slaveSocket?.send(URLSessionWebSocketTask.Message.string(str))
              
                // recreate
                DispatchQueue.main.async {
                    self.lastWrite = overview
                }
            } catch  {
                self.env.slaveState = .none
                completion()
            }
        }
    }
    
    func saveLocal() {
        guard let total = try? JSONEncoder().encode(self.env.schemeHolder) else {
            return
        }
       
        let dayOfWeek = Calendar.current.component(.weekday, from: .now) - 1
        
        save_scheme(total, to: "\(daysOfWeek[dayOfWeek]).json")
        save_scheme(total, to: "latest.json")
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
                item.state.progress = -1
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
        query.timeMin = GTLRDateTime(date: Date.now.startOfDay() - TimeInterval.day)
        query.timeMax = GTLRDateTime(date: Date.now.startOfDay() + TimeInterval.week + TimeInterval.day)
        query.singleEvents = true
        query.orderBy = kGTLRCalendarOrderByStartTime
        
        // replace gsyncs...
        for (i, scheme) in self.env.schemes.enumerated() {
            if scheme.syncs_to_gsync {
                
                service.executeQuery(query) { (_, result, error) in
                    DispatchQueue.main.async {
                        if let error = error {
                            // Handle the error
                            self.env.schemes[i].scheme_list.schemes.insert(SchemeItem(state: [SchemeSingularState()], text:  "ERR_{\(error.localizedDescription)}", repeats: .None, indentation: 0), at: 0)
                            print("Calendar events query error: \(error.localizedDescription)")
                            return
                        }
                        
                        if self.env.slaveState != .write {
                            return
                        }
                        
                        struct GCSummary : Hashable {
                            let text: String
                            let start: Date
                            let end: Date
                        }
                       
                        var old_map : [GCSummary:UUID] = [:]
                        for old in self.env.schemes[i].scheme_list.schemes {
                            let summary = GCSummary(text: old.text, start: old.start!, end: old.end!)
                            old_map[summary] = old.id
                        }
                        self.env.schemes[i].scheme_list.schemes = []
                        
                        // Process the events returned in the response
                        if let events = (result as? GTLRCalendar_Events)?.items {
                            for (j, event) in events.enumerated() {
                                guard let start = event.start?.dateTime?.date, let end = event.end?.dateTime?.date else {
                                    continue
                                }
                                
                                let summary = GCSummary(text: event.summary ?? "", start: start, end: end)
                                let old = old_map[summary]
                                let id = old ?? UUID()
                                
                                let finished = Date.now > end ? -1 : 0
                                let item = SchemeItem(id: id,
                                                      state: [SchemeSingularState(progress: finished)],
                                                      text: (event.summary ?? ""),
                                                      start: start,
                                                      end: end,
                                                      repeats: .None,
                                                      indentation: 0)
                                
                                self.env.schemes[i].scheme_list.schemes.insert(item, at: j)
                            }
                        }
                    }
                }
            }
        }
    }

    func notificationControl() {
        // remove all current scheduled notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            DispatchQueue.main.async {
                // schedule all new notifications
                let flat = self.env.schemes.map { ObservedObject(initialValue: $0) }
                    // start of day so we can cancel null calendar events
                    .flattenEventsInRange(start: Calendar.current.startOfDay(for: .now), end: nil, schemeTypes: [.reminder, .assignment, .event])
                    .sorted(by: { $0.notificationStart < $1.notificationStart })
                
                struct FullIndex: Hashable {
                    let scheme_id:UUID
                    let item_id: UUID
                    let index: Int
                }
                
                var completed: Set<FullIndex> = Set()
                for event in flat {
                    if event.state.progress == -1 {
                        completed.insert(FullIndex(scheme_id: event.scheme_id, item_id: event.id.uuid, index: event.id.index))
                    }
                }
                
                var toDelete: [String] = []
                for notification in notifications {
                    guard let scheme_id = UUID(uuidString: notification.request.content.userInfo["scheme_id"] as! String) else {
                        continue
                    }
                    guard let item_id = UUID(uuidString: notification.request.content.userInfo["item_id"] as! String) else {
                        continue
                    }
                    guard let index = Int(notification.request.content.userInfo["index"] as! String) else {
                        continue
                    }
                    
                    if completed.contains(FullIndex(scheme_id: scheme_id, item_id: item_id, index: index)) {
                        toDelete.append(notification.request.identifier)
                    }
                }
                
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toDelete)
                
                
                var count = 0
                for event in flat {
                    if event.notificationStart < .now || event.state.progress == -1 {
                        continue
                    }
                    
                    count += 1
                    if count > 32 {
                        break
                    }
                    
                    let content = UNMutableNotificationContent()
                    content.title = event.text + " [\(event.path[0])]"
                    // duplicate code...
                    var string = ""
                    if let start = event.start {
                        string += start.timeString
                        string += " \u{2192}"
                    }
                    if let end = event.end {
                        if string.count == 0 {
                            string += "\u{2192} " + end.timeString
                        }
                        else {
                            string += " " + end.timeString
                        }
                    }
                    content.body = string
                    content.categoryIdentifier = "nutq-reminder"
                    content.sound = .defaultCritical
                    content.userInfo["scheme_id"] = event.scheme_id.uuidString
                    content.userInfo["item_id"] = event.id.uuid.uuidString
                    content.userInfo["index"] = event.id.index.description
                    
                    let id = event.id.uuid.uuidString + event.id.index.description
                    let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.notificationStart), repeats: false)
                    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                    
                    let notificationCenter = UNUserNotificationCenter.current()
                    notificationCenter.add(request) { err in }
                }
            }
        }
    }
    
    func loadFileSystem() {
        self.stealSlave()
    }
    
    func saveFileSystem(_ completion: @escaping () -> ()) {
        DispatchQueue.main.async {
            self.updateUpstream(completion)
        }
    }
    
    func force(_ completion: @escaping () -> ()) {
        self.stateControl()
        self.notificationControl()
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

public final class EnvState: ObservableObject, DatastoreManager {
    static var shared: EnvState!
    
    var clock: AnyCancellable?
    var slowClock: AnyCancellable?
    
    
    @Published var stdTime: Date = .now
    @Published var scheme: UUID? = unionNullUUID
    @Published var esotericToken: EsotericUser? = nil {
        didSet {
            // save 
            UserDefaults(suiteName: appGroup)?.setValue(try! JSONEncoder().encode(esotericToken), forKey: "esoteric_token")
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
        let raw = UserDefaults(suiteName: appGroup)?.data(forKey: "esoteric_token")
        esotericToken = raw != nil ? try? JSONDecoder().decode(EsotericUser.self, from: raw!) : nil
        manager = SystemManager(env: self)
        clock = Timer.publish(every: saveRate, on: .main, in: .common)
            .autoconnect()
            .sink { val in
                self.stdTime = val // makes it so clock position is not out of data
                if self.slaveState == .write {
                    self.manager.stateControl()
                    self.manager.saveFileSystem { }
                }
            }
        
        slowClock = Timer.publish(every: saveRate * 4, on: .main, in: .common)
            .autoconnect()
            .sink { val in
                self.stdTime = val // makes it so clock position is not out of data
                if self.slaveState == .write {
                    self.manager.gsyncControl() // handled on next iteration ...
                    self.manager.notificationControl()
                }
            }
        
        self.manager.loadFileSystem()
        self.startup()
        
        Self.shared = self
    }
    
    public func closeSlave() {
        self.manager.closeSlave()
    }
    
    public func stealSlave() {
        if slaveState == SlaveMode.none {
            self.scheme = unionNullUUID
        }
        self.manager.stealSlave()
    }
    
    public func startup() {
        GIDSignIn.sharedInstance.restorePreviousSignIn() { user, error in
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
    var esotericToken: EsotericUser? = nil
    var schemeHolder = SchemeHolder(schemes: [])
    var schemes: [SchemeState] {
        get { schemeHolder.schemes }
        set { schemeHolder.schemes = newValue }
    }
    var slaveState: SlaveMode = .none
    var manager: SystemManager!
    
    init() {
        let raw = UserDefaults(suiteName: appGroup)?.data(forKey: "esoteric_token")
        esotericToken = raw != nil ? try? JSONDecoder().decode(EsotericUser.self, from: raw!) : nil
        manager = SystemManager(env: self)
    }
    
    func retrieve(_ completion: @escaping (_ schemes: SchemeHolder?) -> (), allow_online: Bool = true) {
        if !allow_online {
            let res: SchemeHolder? = load_scheme(from: "latest.json")
            schemeHolder = res ?? SchemeHolder(schemes: [])
            manager.stateControl()
            completion(res)
            return
        }
        
        Task.init {
            var res: SchemeHolder? = nil
            
            if allow_online {
                res = await auth_request(env: self, "/sync/bucket/nutq")
            }
            
            DispatchQueue.main.async {
                if res == nil {
                    res = load_scheme(from: "latest.json")
                }
                else if let data = try? JSONEncoder().encode(res) {
                    save_scheme(data, to: "latest.json")
                }
                
                self.schemeHolder = res ?? SchemeHolder(schemes: [])
                self.manager.stateControl()
                completion(res)
            }
        }
    }
}

public enum MenuAction: CustomStringConvertible {
    case gotoUnion
    case nextScheme
    case prevScheme
    
    case toggle
    
    case toggleAvailableView
    case disableAvailable
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
        case .toggleAvailableView:
            return "Toggle Available View"
        case .disableAvailable:
            return "Disable Available"
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
