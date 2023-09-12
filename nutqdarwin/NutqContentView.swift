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
        Group {
            if env.esotericToken == nil {
                Auth()
            }
            else if case .none = env.slaveState {
                VStack {
                    Text("Slave Unavailable")
                    Button("Steal Slave") {
                        env.stealSlave()
                    }
                }
            }
            else if case .loading = env.slaveState {
                Text("Loading")
            }
            else {
                NavigationView {
                    Sidebar()
                    Union()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(env)
        .onChange(of: undo) { (old, undo) in
            env.undoManager = undo
            undo?.groupsByEvent = true
        }
    }
}

#Preview {
    NutqContentView()
}
