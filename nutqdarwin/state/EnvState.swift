//
//  Environment.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import Foundation
import SwiftUI

public let debugSchemes = [
    SchemeState(name: "Monocurl", colorIndex: 1, schemes: []),
    SchemeState(name: "UCSD", colorIndex: 2, schemes: []),
    SchemeState(name: "MaXentric", colorIndex: 3, schemes: []),
    SchemeState(name: "Nutq", colorIndex: 4, schemes: []),
    SchemeState(name: "Research", colorIndex: 5, schemes: []),
    SchemeState(name: "Ideas", colorIndex: 6, schemes: []),
]

public struct SchemeItem {
    public var state: Int // 0 = not complete, -1 = finished. Open to intermediate states
    public var description: String
    
    public var start: Date?
    public var end: Date?
    
    public var children: [SchemeItem]? // in which case start and end are guaranteed to be a procedure
}

public struct SchemeState: Identifiable {
    public let id = UUID()
    
    public var name: String
    public var colorIndex: Int
    public var email: String?
    
    public var schemes: [SchemeItem]
}

public class EnvState: ObservableObject {
    weak var undoManager: UndoManager?
    @Published var scheme: UUID? = nil
    @Published var schemes: [SchemeState] = debugSchemes
    
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
}
