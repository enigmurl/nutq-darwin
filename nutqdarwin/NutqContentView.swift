//
//  NutqContentView.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 5/28/23.
//

import SwiftUI

struct NutqContentView: View {
    @Environment(\.undoManager) private var undo: UndoManager?
    @StateObject private var env = EnvState()
    
    var body: some View {
        NavigationView {
            Sidebar()
            
            Union()
        }
        .environmentObject(env)
        .onChange(of: undo) { undo in
            env.undoManager = undo
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        NutqContentView()
    }
}
