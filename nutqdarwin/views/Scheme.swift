//
//  Scheme.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI

#if os(macOS)
import Cocoa
#else
import UIKit
#endif

struct Scheme: View {
    @EnvironmentObject var env: EnvState
    @Binding var scheme: SchemeState
    
    func removeFocus() {
        DispatchQueue.main.async {
            #if os(macOS)
                NSApp.keyWindow?.makeFirstResponder(nil)
            #else
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
    }
    
    var body: some View {
        HStack {
            #if os(macOS)
                Upcoming(schemes: [$scheme])
                Divider()
            #endif 
            Tree(scheme: $scheme)
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
       
    }
}

struct Scheme_Previews: PreviewProvider {
    static var previews: some View {
        Scheme(scheme: .constant(debugSchemes[0]))
    }
}
