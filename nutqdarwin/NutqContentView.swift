//
//  NutqContentView.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 5/28/23.
//

import SwiftUI

struct NutqContentView: View {
    @Environment(\.undoManager) private var undo: UndoManager?
    @EnvironmentObject var env: EnvState
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationView {
            Sidebar()
            Union()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
