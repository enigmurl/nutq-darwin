//
//  Sidebar.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI

struct SidebarLabel: View {
    @Binding var deletionID: UUID?
    
    let scheme: Binding<SchemeState>?
    
    @State var showingEditingWindow = false
    
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
                #if os(iOS)
                Text(scheme?.wrappedValue.name ?? "Union")
                    .font(.title3)
                
                #else
                if let scheme = scheme {
                    TextField("", text: scheme.name)
                        .padding(.leading, -4)
                        .textFieldStyle(.plain)
                        .font(.title3)
                }
                else {
                    Text("Union")
                        .padding(.leading, 4)
                        .font(.title3)
                }
                #endif

            } icon: {
                TagView(index: scheme?.colorIndex ?? nil)
            }
        }
        .tag(scheme?.wrappedValue.id ?? union_uuid)
        .swipeActions(allowsFullSwipe: false) {
            // necessarily iOS
            if scheme != nil {
                /* role destructive deletes it automatically for some reason */
                Button("Delete") {
                    self.deletionID = self.scheme?.wrappedValue.id
                }
                .tint(.red)
                
                Button("Edit") {
                    showingEditingWindow = true
                }
            }
        }
        .popover(isPresented: $showingEditingWindow) {
            Label {
                TextField("", text: scheme!.name)
                    .padding(.leading, -4)
                    .textFieldStyle(.plain)
                    .font(.title3)
            } icon: {
                TagView(index: scheme?.colorIndex ?? nil)
            }
            .frame(minWidth: 140)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var env: EnvState
        
    @State var deleteID: UUID? = nil
    
    func delete(uuid: UUID?) {
        deleteID = uuid
    }
    
    var body: some View {
        List(selection: $env.scheme) {
            SidebarLabel(deletionID: $deleteID, scheme: nil)
            
            ForEach($env.schemes, editActions: .move) { scheme in
                SidebarLabel(deletionID: $deleteID, scheme: scheme)
            }
        }
        .listStyle(.sidebar)
        #if os(macOS)
        .onDeleteCommand {
            if self.env.scheme != union_uuid {
                self.delete(uuid: self.env.scheme)
            }
        }
        #endif
        .alert("Confirm Deletion",
               isPresented: Binding(
                    get: {deleteID != nil},
                    set: {deletion in deleteID = nil
               }),
               presenting: deleteID) { id in
            
            Button(role: .destructive) {
                self.env.delete(uuid: id)
            } label: {
                Text("Delete \(env.schemes.first(where: {$0.id == id})!.name)?")
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
