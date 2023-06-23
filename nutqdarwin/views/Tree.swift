//
//  Tree.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/13/23.
//

import SwiftUI

struct Tree: View {
    @Binding var scheme: SchemeState
    
    var body: some View {
        // allows standard editing configuration
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Tree_Previews: PreviewProvider {
    static var previews: some View {
        Tree(scheme: .constant(debugSchemes[0]))
    }
}
