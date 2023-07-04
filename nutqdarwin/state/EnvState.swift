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

let unionNullUUID = UUID(uuidString: "00000000-0000-0000-0000-ffffffffffff")!

struct Datastore: Codable {
    let signed: Date
    var schemes: [SchemeState]
}

class SystemManager {
    unowned var env: EnvState
    
    var loadedFileSchemes: Datastore! // whatever is currently known to be in the file system
    var loadediCloudSchemes: Datastore?
    
    init(env: EnvState) {
        self.env = env
        
//        BGTaskScheduler.shared
    }
    
    func fileSystemSync() {
        
    }
    
    func iCloudSync() {
        
    }
    
    func googleCalendarPoll() {
        
    }
    
    func stateControl() {
        
    }
    
    func reminderControl() {
        
    }
    
    func runTasks() {
        // 1. sync with file system (handled by envState)
        // 2. sync with iCloud
        // 3. sync with google calendar
        // 4. state control: all calendar events that are unfinished that have already passed must be marked as finished
        // 5. setting up reminders
    }
    
    var url: URL! {
        try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "main.nqd")
    }
    
    func loadFileSystem() {
        defer {
            self.env.schemes = self.loadedFileSchemes.schemes
        }
        
        guard let data = try? Data(contentsOf: self.url) else {
            NSLog("[SystemManager] loading default schemes")
            self.loadedFileSchemes = Datastore(signed: .distantPast, schemes: [])
            return
        }
        
        self.loadedFileSchemes = try! JSONDecoder().decode(Datastore.self, from: data)
        NSLog("[SystemManager] loaded file system schemes")
    }
    
    func saveFileSystem() {
        if loadedFileSchemes.schemes != self.env.schemes {
            loadedFileSchemes = Datastore(signed: .now, schemes: self.env.schemes)
            let data = try! JSONEncoder().encode(loadedFileSchemes)
            try! data.write(to: self.url)
            NSLog("[SystemManager] committing file system save")
        }
    }
    
    func force() {
        self.saveFileSystem()
    }
}

public class EnvState: ObservableObject {
    var clock: AnyCancellable?
    
    @Published var stdTime: Date = .now
    @Published var scheme: UUID? = unionNullUUID
    @Published var schemes: [SchemeState] = debugSchemes
    
    var manager: SystemManager!
    weak var undoManager: UndoManager?
   
    init() {
        manager = SystemManager(env: self)
        clock = Timer.publish(every: .minute, on: .main, in: .common)
            .autoconnect()
            .sink(receiveValue: { val in
                self.stdTime = val
                self.manager.saveFileSystem()
            })

        self.manager.loadFileSystem()
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
    
    public func writeBinding<T>(binding: Binding<T>, newValue: T) where T: Equatable {
        let oldValue = binding.wrappedValue
        
        if oldValue != newValue {
            binding.wrappedValue = newValue
            
            undoManager?.registerUndo(withTarget: self, handler: {$0.writeBinding(binding: binding, newValue: oldValue)})
        }
    }
    
    deinit {
        manager.force()
    }
}

public enum MenuAction: CustomStringConvertible {
    case gotoUnion
    case nextScheme
    case prevScheme
    
    case indent
    case deindent
    case delete
    
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
        case .indent:
            return "Indent"
        case .deindent:
            return "Deindent"
        case .delete:
            return "Delete"
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
