//
//  Environment.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import Foundation
import SwiftUI


let unionNullUUID = UUID(uuidString: "00000000-0000-0000-0000-ffffffffffff")!


public class EnvState: ObservableObject {
    @Published var scheme: UUID? = unionNullUUID
    @Published var schemes: [SchemeState] = debugSchemes
    
    weak var undoManager: UndoManager?
    
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
    
    public func writeBinding<T>(binding: Binding<T>, newValue: T) {
        let oldValue = binding.wrappedValue
        binding.wrappedValue = newValue
        
        undoManager?.registerUndo(withTarget: self, handler: {$0.writeBinding(binding: binding, newValue: oldValue)})
    }
}
