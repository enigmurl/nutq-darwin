//
//  Theme.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/12/23.
//

import Foundation
import SwiftUI

let maxColorIndex = 6;

public func colorIndexToColor(_ index: Int) -> Color {
    switch (index) {
    case 1:
        return .red
    case 2:
        return .orange
    case 3:
        return .yellow
    case 4:
        return .green
    case 5:
        return .blue
    case 6:
        return .purple
    default:
        return .primary
    }
}

struct TagView: View {
    var index: Binding<Int>?
    
    @State var showingDropDown = false
    
    private func square(index: Int) -> some View {
        Image(systemName: "square.fill")
            .resizable()
            .frame(width: 20, height: 18)
            .foregroundColor(colorIndexToColor(index))
    }
    
    var body: some View {
        self.square(index: self.index?.wrappedValue ?? 0)
            .onTapGesture {
                if index != nil {
                    showingDropDown = true
                }
            }
            .popover(isPresented: $showingDropDown) {
                HStack {
                    ForEach(Array(1 ... maxColorIndex), id: \.self) { i in
                        self.square(index: i)
                            .onTapGesture {
                                self.index?.wrappedValue = i
                            }
                    }
                }
                .padding(8)
            }
    }
    
}
