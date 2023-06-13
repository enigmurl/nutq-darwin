//
//  Scheme.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import Cocoa
import SwiftUI

struct Scheme: View {
    @EnvironmentObject var env: EnvState
    @Binding var scheme: SchemeState
    
    func removeFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    var body: some View {
        HStack {
            CalendarView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .onTapGesture {
                   removeFocus()
                }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    TagView(index: $scheme.colorIndex)
                    
                    Text(scheme.name)
                        .font(.headline)
                }
                .frame(width: 140, alignment: .leading)
            }
        }
       
        // main editing tree
        // Right sidebar: upcoming rising and falling edges
    }
}

struct Scheme_Previews: PreviewProvider {
    static var previews: some View {
        Scheme(scheme: .constant(debugSchemes[0]))
    }
}
