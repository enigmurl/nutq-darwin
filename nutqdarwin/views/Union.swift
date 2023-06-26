//
//  Home.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI


struct Union: View {
    @EnvironmentObject var env: EnvState
    
    #if os(iOS)
    @State var showingUpcoming = false
    #endif
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            #if os(macOS)
                Upcoming(schemes: ($env.schemes).map({$0}))
                Divider()
                    .opacity(0.2)
            #endif
            Calendar(schemes: ($env.schemes).map({$0}))
        }
        #if os(iOS)
        .sheet(isPresented: $showingUpcoming) {
            Upcoming(schemes: ($env.schemes).map({$0}))
                .padding(.top, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement:. principal) {
                HStack {
                    TagView(index: nil)
                   
                    Text("Union")
                        .font(.headline)
                }
                .frame(width: 140, alignment: .leading)
            }
            
            #if os(iOS)
            ToolbarItem {
                Button("Soon") {
                    showingUpcoming = true
                }
            }
            #endif
        }
    }
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        Union()
    }
}
