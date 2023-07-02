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
    
    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            Union()
        }
        .navigationSplitViewStyle(.prominentDetail)
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
