//
//  Home.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import SwiftUI
import GoogleSignIn
import GoogleAPIClientForRESTCore


struct Union: View {
    @EnvironmentObject var env: EnvState
    
    @State var shown = false
    
    #if os(iOS)
    @State var showingUpcoming = false
    #endif
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            #if os(macOS)
            Upcoming(schemes: env.schemes.map { ObservedObject(wrappedValue: $0) })
                Divider()
                    .opacity(0.2)
            #endif
            CalendarView(schemes:  env.schemes.map { ObservedObject(wrappedValue: $0) })
        }
        .onAppear {
            if !shown {
                DispatchQueue.main.async {
                    shown = true
                    env.stdTime = .now
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingUpcoming) {
            Upcoming(schemes: env.schemes.map { ObservedObject(wrappedValue: $0) })
                .padding(.top, 20)
                .presentationDetents([.medium, .large])
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
                #if os(macOS)
                .frame(width: 140, alignment: .leading)
                #endif
            }
            
            #if os(iOS)
            ToolbarItem {
                Button("Soon") {
                    showingUpcoming = true
                }
            }
            #else
            ToolbarItem(placement: .navigation) {
                Button(GIDSignIn.sharedInstance.currentUser?.profile?.email ?? "Add G-Sync") {
                    guard let window = NSApplication.shared.keyWindow else {
                        return
                    }
                  
                    GIDSignIn.sharedInstance.signIn(withPresenting: window, hint: nil, additionalScopes:  ["https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/calendar.events"]) { result, error in
                    }
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
