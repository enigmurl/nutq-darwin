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
    @ObservedObject var scheme: SchemeState
    
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
        HStack(spacing: 0) {
            #if os(macOS)
                Upcoming(schemes: [_scheme])
                Divider()
            #endif 
            
            Tree(scheme: scheme.scheme_list)
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
                    TagView(index: $scheme.color_index)
                    
                    Text(scheme.name)
                        .font(.headline)
                }
#if os(macOS)
                .frame(minWidth: 140, alignment: .leading)
#endif
            }
            
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                Button(scheme.syncs_to_gsync ? "unset gsync" : "set gsync") {
                    if scheme.syncs_to_gsync {
                        scheme.syncs_to_gsync = false
                    }
                    else {
                        for i in 0 ..< env.schemes.count {
                            env.schemes[i].syncs_to_gsync = false
                        }
                        
                        scheme.syncs_to_gsync = true
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
       
    }
}
