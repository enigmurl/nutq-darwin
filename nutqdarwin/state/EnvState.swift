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

#if os(macOS)
class Datastore: NSDocument {
    unowned var env: EnvState
    var lastSaveCount: Int = 0
    var modCount: Int = 0
        
    init(env: EnvState) {
        self.env = env
    }
   
    override func data(ofType typeName: String) throws -> Data {
        NSLog("[Datastore] perform write")
        return try JSONEncoder().encode(env.schemes)
    }
    
    override func read(from data: Data, ofType typeName: String) throws {
        NSLog("[Datastore] perform read")
        self.env.schemes = try JSONDecoder().decode([SchemeState].self, from: data)
    }
    
    func save(_ completion: @escaping () -> ()) {
        guard self.lastSaveCount < self.modCount else {
            return
        }
        
        self.lastSaveCount = self.modCount
        
        Task.init {
            try! await self.env.document.save(to: Self.url, ofType: "nqd", for: .saveAsOperation)
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func load() {
        try? self.env.document.revert(toContentsOf: Self.url, ofType: "nqd")
    }
}
#else
class Datastore: UIDocument {
    unowned var env: EnvState
    var lastSaveCount: Int = 0
    var modCount: Int = 0
    
    init(env: EnvState) {
        self.env = env
        super.init(fileURL: Self.url)
    }
   
    override func contents(forType typeName: String) throws -> Any {
        NSLog("[Datastore] perform write")
        return try JSONEncoder().encode(env.schemes)
    }
    
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else {
            throw NSError(domain: "[Datastore]", code: 1)
        }
    
        NSLog("[Datastore] perform read")
        self.env.schemes = try JSONDecoder().decode([SchemeState].self, from: data)
    }
    
    func save(_ completion: @escaping () -> ()) {
        guard self.lastSaveCount < self.modCount else {
            return
        }
        
        self.lastSaveCount = self.modCount
        
        Task.init {
            let res = await self.env.document.save(to: Self.url, for: .forOverwriting)
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func load() {
        Task.init {
            let res = await self.open()
        }
    }
}
#endif

extension Datastore {
    class var url: URL! {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("main.nqd")
    }
    
    
}

class SystemManager {
    unowned var env: EnvState
    
    var loadedFileSchemes: Datastore! // whatever is currently known to be in the file system
    var loadediCloudSchemes: Datastore?
    
    init(env: EnvState) {
        self.env = env
    }
    
    func fileSystemSync() {
        
    }
    
    func iCloudSync() {
        
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
    
    func loadFileSystem() {
        self.env.document.load()
    }
    
    func saveFileSystem(_ completion: @escaping () -> ()) {
        self.env.document.save(completion)
    }
    
    func force(_ completion: @escaping () -> ()) {
        self.saveFileSystem(completion)
    }
}

public class EnvState: ObservableObject {
    var clock: AnyCancellable?
    
    @Published var stdTime: Date = .now
    @Published var scheme: UUID? = unionNullUUID
    
    
    /* doubly buffered */
    var document: Datastore!
    @Published var schemes: [SchemeState] = [] {
        didSet {
            document.modCount += 1
        }
    }
    
    var manager: SystemManager!
    weak var undoManager: UndoManager?
   
    init() {
        manager = SystemManager(env: self)
        document = Datastore(env: self)
        clock = Timer.publish(every: .minute, on: .main, in: .common)
            .autoconnect()
            .sink { val in
                self.stdTime = val // makes it so clock position is not out of data
                self.manager.saveFileSystem({})
            }

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
        manager.force({})
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
