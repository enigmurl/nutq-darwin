//
//  Auth.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 8/25/23.
//

import SwiftUI

struct Auth: View {
    @EnvironmentObject var env: EnvState
    
    @State var username = ""
    @State var password = ""
    @State var error = ""
    
    var body: some View {
        Form {
            VStack {
                TextField("username", text: $username)
                TextField("password", text: $password)
              
                if error.count > 0 {
                    Text(error)
                        .foregroundColor(.red)
                }
                
                Button("Go") {
                    Task.init {
                        error = ""
                        let res = await sign_in(
                            env: env,
                            username: username,
                            password: password
                        )
                        if !res {
                            error = "Error"
                        }
                    }
                }
            }
            .frame(maxWidth: 400, alignment: .center)
            .padding()
        }
    }
}

#Preview {
    Auth()
}
