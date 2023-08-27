//
//  Sidebar.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI

struct SidebarLabel: View {
    @EnvironmentObject var env: EnvState
    @Binding var deletionID: UUID?
    
    var scheme: Binding<SchemeState>?
    
    @State var showingEditingWindow = false
    
    var body: some View {
        NavigationLink {
            if let scheme = scheme {
                Scheme(scheme: scheme.wrappedValue)
            }
            else {
                Union()
            }
        } label: {
            Label {
                #if os(iOS)
                Text(undoableScheme?.wrappedValue.name ?? "Union")
                    .font(.title3)
                #else
                if let scheme = scheme {
                    TextField("", text: scheme.name)
                        .textFieldStyle(.plain)
                        .font(.title3)
                }
                else {
                    Text("Union")
                        .font(.title3)
                }
                #endif

            } icon: {
                TagView(index: scheme?.color_index ?? nil)
            }
        }
        .tag(scheme?.wrappedValue.id ?? unionNullUUID)
        .swipeActions {
            // necessarily iOS
            if scheme != nil {
                /* role destructive deletes it automatically for some reason */
                Button("Delete") {
                    self.deletionID = scheme?.wrappedValue.id
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
                TagView(index: scheme?.color_index ?? nil)
            }
            .frame(minWidth: 140)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

    
struct Sidebar: View {
    @EnvironmentObject private var menu: MenuState
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
            
            Button("New") {
                env.insert(scheme: SchemeState(name: "Scheme", color_index: 1, scheme_list: SchemeItemList(schemes: [blankEditor("")])), at: env.schemes.count)
            }
            #if os(macOS)
            .buttonStyle(.link)
            #endif
            .frame(maxWidth: .infinity)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 175)
        #if os(macOS)
        .onDeleteCommand {
            if self.env.scheme != unionNullUUID {
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
       .onReceive(menu) { action in
           switch (action) {
           case .gotoUnion:
               self.env.scheme = unionNullUUID
           case .prevScheme:
               let index = max(-1, (self.env.schemes.firstIndex(where: {$0.id == self.env.scheme ?? unionNullUUID}) ?? -1) - 1)
               self.env.scheme = index == -1 ? unionNullUUID : self.env.schemes[index].id
           case .nextScheme:
               let index = min(self.env.schemes.count - 1, (self.env.schemes.firstIndex(where: {$0.id == self.env.scheme ?? unionNullUUID}) ?? -1) + 1)
               self.env.scheme = index == -1 ? unionNullUUID : self.env.schemes[index].id
           default:
               break
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
