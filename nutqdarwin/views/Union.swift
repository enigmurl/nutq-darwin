//
//  Home.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI


struct Union: View {
    @EnvironmentObject var env: EnvState
    
    var body: some View {
        HStack {
            Upcoming(schemes: ($env.schemes).map({$0}))
            #if os(macOS)
                Divider()
                Calendar()
            #endif
        }
        .toolbar {
            ToolbarItem(placement:. principal) {
                HStack {
                    TagView(index: nil)
                   
                    Text("Union")
                        .font(.headline)
                }
                .frame(width: 140, alignment: .leading)
            }
        }
        
        // calendar view
        
        // right side: upcoming edges
    }
}

struct Home_Previews: PreviewProvider {
    static var previews: some View {
        Union()
    }
}
