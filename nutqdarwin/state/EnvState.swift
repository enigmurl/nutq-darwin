//
//  Environment.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import Foundation
import SwiftUI
import Combine


let unionNullUUID = UUID(uuidString: "00000000-0000-0000-0000-ffffffffffff")!

public class EnvState: ObservableObject {
    var clock: AnyCancellable?
    
    @Published var stdTime: Date = .now
    @Published var scheme: UUID? = unionNullUUID
    @Published var schemes: [SchemeState] = debugSchemes
    
    weak var undoManager: UndoManager?
    
    init() {
        clock = Timer.publish(every: .minute, on: .main, in: .common)
            .autoconnect()
            .assign(to: \EnvState.stdTime, on: self)
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
