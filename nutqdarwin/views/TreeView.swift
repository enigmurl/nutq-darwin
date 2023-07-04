//
//  TreeView.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 7/3/23.
//

import SwiftUI

enum EditingMode {
    case editing
}

struct EditorState {
    var mode: EditingMode
    
}

#if os(macOS)
class TextView: NSTextView {
    
}


struct TreeView: NSViewRepresentable {
    @State var mode = EditingMode.editing

    func makeNSView(context: NSViewRepresentableContext<Self>) -> TextView {
        let ret = TextView()
        
        return ret
    }
    
    func updateNSView(_ nsView: TextView, context: NSViewRepresentableContext<Self>) {
        
    }
}

struct TreeView_Previews: PreviewProvider {
    static var previews: some View {
        TreeView()
    }
}
#endif
