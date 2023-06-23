//
//  Upcoming.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/13/23.
//

import SwiftUI

// a bit redundant, but should be fine
fileprivate extension Date {
    var dateString: String {
        let diff = dayDifference(with: .now)
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MM-dd"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        let day: String
        if diff == 0 {
            day = "today"
        }
        else if diff == 1 {
            day = "tomorrow"
        }
        else {
            day = dayFormatter.string(from: self)
        }
        
        let time = timeFormatter.string(from: self)
        
        return day + " " + time
    }
    
    // time interval starts at midnight
    func dayDifference(with date: Date) -> Int {
        let cal = NSCalendar(identifier: .gregorian)!
        let ourStart = cal.startOfDay(for: self)
        let theirStart = cal.startOfDay(for: date)
        
        return Int(ourStart.timeIntervalSince(theirStart) / .day)
    }
}

struct UpcomingAssignment: View {
    @EnvironmentObject var env: EnvState
    let item: SchemeSingularItem
    
    var color: Color {
        if (item.state == -1) {
            return .gray
        }
        return colorIndexToColor(item.colorIndex)
    }
    
    var dateColor: Color {
        let time = self.item.start ?? self.item.end!
        // same day
        if time.dayDifference(with: .now) <= 0 {
            return Color(red: 1, green: 0.5, blue: 0.5)
        }
        else if time.dayDifference(with: .now) <= 1 {
            return Color(red: 1, green: 0.7, blue: 0.7)
        }
        else {
            return .white
        }
    }
    
    var dateString: some View {
        VStack(alignment: .trailing) {
            Group {
                if let start = self.item.start {
                    if self.item.end != nil {
                        Text("From " + start.dateString)
                    }
                    else {
                        Text("Starts " + start.dateString)
                    }
                }
                if let end = self.item.end {
                    if self.item.start != nil {
                        Text("To " + end.dateString)
                    }
                    else {
                        Text("Due " + end.dateString)
                    }
                }
            }
            .font(.caption2.monospaced())
            .bold()
            .foregroundColor(self.dateColor)
            
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
     
        .onTapGesture(count: 1) {
            self.switchState()
        }
        
        .tag(item.id)
    }
    
    func switchState() {
        withAnimation {
            if (self.item.state != -1) {
                self.env.writeBinding(binding: self.item.$state, newValue: -1)
            }
            else {
                self.env.writeBinding(binding: self.item.$state, newValue: 0)
            }
        }
    }
}

struct Upcoming: View {
    let assignmentSchemes: [SchemeSingularItem]
    let upcomingSchemes: [SchemeSingularItem]
    
    init(schemes: [Binding<SchemeState>]) {
        let calendar = NSCalendar(identifier: .gregorian)!
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
                        .padding(3)
                        .background( Color.blue.opacity(($0.offset + parity) % 2 == 0 ? 0 : 0.1)
                            .cornerRadius(2)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    
    var body: some View {
        /* gives a list of upcoming events, assignments, and reminders */
        /* if recurring, only gives the first one */
        // so we have left side is the upcoming assignments
        // then reminders and events
        ScrollView {
            self.itemList(title: "Assignments", items: self.assignmentSchemes, parity: 0)
            
            self.itemList(title: "Upcoming", items: self.upcomingSchemes, parity: self.assignmentSchemes.count)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: 320, maxHeight: .infinity)
    }
}

struct Upcoming_Previews: PreviewProvider {
    static var previews: some View {
        Upcoming(schemes: debugSchemes.map({Binding.constant($0)}))
    }
}
