//
//  Home.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI

struct CalendarView: View {
    var body: some View {
        Text("Not implemented yet")
    }
}

struct Union: View {
    var body: some View {
        HStack {
            CalendarView()
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
