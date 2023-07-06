//
//  Upcoming.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/13/23.
//

import SwiftUI

struct UpcomingAssignment: View {
    @EnvironmentObject var env: EnvState
    let item: SchemeSingularItem
    
    var color: Color {
        if (item.state == -1) {
            return .gray
        }
        return colorIndexToColor(item.colorIndex)
    }
    
    var dateString: some View {
        VStack(alignment: .trailing) {
            Group {
                if let start = self.item.start {
                    if self.item.end != nil {
                        Text(start.dateString)
                    }
                    else {
                        Text("Starts " + start.dateString)
                    }
                }
                if let end = self.item.end {
                    if let s = self.item.start {
                        Text((end.dayDifference(with: s) == 0 ? end.timeString : end.dateString))
                    }
                    else {
                        Text("Due " + end.dateString)
                    }
                }
            }
            .font(.caption2.monospaced())
            .multilineTextAlignment(.trailing)
            .bold()
            .foregroundColor(self.item.dateColor)
            
            Spacer()
        }
    }
    
    var path: some View {
        Text(self.item.path.joined(separator: "\u{00bb}"))
            .font(.caption2)
            .bold()
            .foregroundColor(color)
    }
    
    var body: some View {
        /* needs to highlight path and title, as well as have option for completing */
        
        //Path
        //Text [time]      [complete or not]
        HStack {
            Rectangle()
                .frame(maxWidth: 1.5, maxHeight: .infinity)
                .foregroundColor(color)
                .saturation(0.4)
        
            VStack(alignment: .leading) {
                self.path
                    .saturation(0.4)
                
                Text(item.text)
            }
            .offset(x: -3)
            
            Spacer()
            
            self.dateString
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
       
        .grayscale(self.item.state == -1 ? 1 : 0)
        .opacity(self.item.state == -1 ? 0.3 : 1)
        .strikethrough(self.item.state == -1, color: .red)
     
        .onTapGesture {
            self.switchState()
        }
        
        .tag(item.id)
    }
    
    func switchState() {
//        withAnimation {
        if (self.item.state != -1) {
            self.item.state = -1
        }
        else {
            self.item.state = 0
        }
//        }
    }
}

struct Upcoming: View {
    let assignmentSchemes: [SchemeSingularItem]
    let upcomingSchemes: [SchemeSingularItem]
    
    init(schemes: [Binding<SchemeState>]) {
        let calendar = NSCalendar.current
        let mainSchemes = schemes.flattenToUpcomingSchemes(start: calendar.startOfDay(for: .now))
        
        self.assignmentSchemes = mainSchemes
            .filter({$0.start == nil && $0.end != nil})
            .sorted(by: {
               // $0.state != -1 && $1.state == -1 || ($0.state != -1) == ($1.state != -1) &&
                $0.end! < $1.end!
            })
        self.upcomingSchemes   = mainSchemes
            .filter({$0.start != nil})
            .sorted(by: {$0.start! < $1.start!})
    }
    
    func title(_ name: String) -> some View {
        Text(name)
            .fontWeight(.medium)
            .opacity(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
    }
    
    func itemList(title: String, items list: [SchemeSingularItem] , parity: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.title(title)
           
            if list.isEmpty {
                Text("None")
                    .frame(maxWidth: .infinity)
            }
            else {
                ForEach(Array(list.enumerated()), id: \.element.id) {
                    UpcomingAssignment(item: $0.element)
                        .padding(4)
                        .background( Color.blue.opacity(($0.offset + parity) % 2 == 0 ? 0 : 0.1)
                            .cornerRadius(3)
                        )
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
    }

    
    var body: some View {
        /* gives a list of upcoming events, assignments, and reminders */
        /* if recurring, only gives the first one */
        // so we have left side is the upcoming assignments
        // then reminders and events
        ScrollView {
            self.itemList(title: "Assignments", items: self.assignmentSchemes, parity: 0)
            
            self.itemList(title: "Upcoming", items: self.upcomingSchemes, parity: 0)
        }
        .padding(.horizontal, 4)
        #if os(macOS)
        .frame(minWidth: 250, maxWidth: 250, maxHeight: .infinity)
        #else
        .frame(minWidth: 250, idealWidth: 250, maxHeight: .infinity)
        #endif
        .padding(.vertical, 8)
    }
}

struct Upcoming_Previews: PreviewProvider {
    static var previews: some View {
        Upcoming(schemes: debugSchemes.map({Binding.constant($0)}))
    }
}
