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
    
    @State var aux: Date? = .now
    @StateObject var test = {
        let ret = blankEditor("")
        ret.repeats = .block(block: .init())
        return ret
    }()
    
    var body: some View {
        Group {
//            if env.esotericToken == nil {
//                Auth()
//            }
//            else {
//                NavigationView {
//                    Sidebar()
//                    Union()
//                }
//            }
            Time(label: "Start", date: $aux, showing: .constant(true))
            Block(showing: .constant(true), schemeNode: test)
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
