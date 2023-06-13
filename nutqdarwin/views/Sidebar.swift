//
//  Sidebar.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI

struct SidebarLabel: View {
    let scheme: Binding<SchemeState>?
    
    var body: some View {
        NavigationLink {
            if let scheme = scheme {
                Scheme(scheme: scheme)
            }
            else {
                Union()
            }
        } label: {
            Label {
                if let scheme = scheme {
                    TextField("", text: scheme.name)
                        .padding(.leading, -4)
                        .textFieldStyle(.plain)
                        .font(.title3)
                }
                else {
                    Text("Union")
                        .font(.title3)
                        .padding(.leading, 4)
                }
            } icon: {
                TagView(index: scheme?.colorIndex ?? nil)
            }
            .tag(scheme?.wrappedValue.id)
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var env: EnvState
    @Environment(\.undoManager) private var undo: UndoManager?
    
    @State var confirmDelete = false
    
    var body: some View {
        List(selection: $env.scheme) {
            SidebarLabel(scheme: nil)
            
            ForEach($env.schemes, editActions: [.delete, .move]) { scheme in
                SidebarLabel(scheme: scheme)
            }
        }
        .listStyle(.sidebar)
        .padding(.top)
        .onDeleteCommand {
            if self.env.scheme != nil {
                confirmDelete = true
            }
        }
        .alert("Confirm Deletion",
               isPresented: $confirmDelete,
               presenting: env.scheme) { _ in
            Button(role: .destructive) {
                self.env.delete(uuid: env.scheme!)
            } label: {
                Text("Delete \(env.schemes.first(where: {$0.id == env.scheme})!.name)?")
            }
        }
    }
}

struct Sidebar_Previews: PreviewProvider {
    static var previews: some View {
        Sidebar()
            .environmentObject(EnvState())
    }
}
