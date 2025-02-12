//
//  Upcoming.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/13/23.
//

import SwiftUI
import Combine

struct UpcomingAssignment: View {
    @EnvironmentObject var env: EnvState
    let item: SchemeSingularItem
    
    var animation: Animation {
        .easeOut(duration: 0.25)
    }
    
    var color: Color {
        if (item.state.progress == -1) {
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
                        Text("At " + start.dateString)
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
            .foregroundStyle(self.item.dateColor)
            
            Spacer()
        }
    }
    
    var path: some View {
        Text(self.item.path.joined(separator: "\u{00bb}"))
            .font(.caption2)
            .bold()
            .animation(self.animation) {
                $0.foregroundStyle(color)
            }
    }
    
    var body: some View {
        /* needs to highlight path and title, as well as have option for completing */
        
        //Path
        //Text [time]      [complete or not]
        HStack {
            Rectangle()
                .frame(maxWidth: 1.5, maxHeight: .infinity)
                .animation(self.animation) {
                    $0.foregroundStyle(color)
                }
                .saturation(0.4)
            
            VStack(alignment: .leading) {
                self.path
                    .saturation(0.4)
                
                Text(item.text)
                    .truncationMode(.tail)
                    .lineLimit(1)
            }
            .offset(x: -3)
            
            Spacer()
            
            self.dateString
        }
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .onTapGesture {
            self.switchState()
        }
        .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
        .animation(self.animation) {
            $0.grayscale(self.item.state.progress == -1 ? 1 : 0)
              .opacity(self.item.state.progress == -1 ? 0.3 : 1)
        }
        .tag(item.id)
    }
    
    func switchState() {
        if (self.item.state.progress != -1) {
            self.item.state.progress = -1
        }
        else {
            self.item.state.progress = 0
        }
    }
}

class RefreshController: ObservableObject {
    @Published var refreshTrigger = 0
    private var debounceTask: Task<Void, Never>?

    func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 100_000)
            await MainActor.run {
                self.refreshTrigger += 1
            }
        }
    }
}

struct Upcoming: View {
    @State var assignmentSchemesIndices: [SchemeSingularItem.IDPath: Int] = [:]
    @State var reminderSchemesIndices: [SchemeSingularItem.IDPath: Int] = [:]
    @State var upcomingSchemesIndices: [SchemeSingularItem.IDPath: Int] = [:]
    @State var assignmentSchemes: [SchemeSingularItem] = []
    @State var reminderSchemes: [SchemeSingularItem] = []
    @State var upcomingSchemes: [SchemeSingularItem] = []
    @StateObject var refreshController = RefreshController()
    
    let schemes: [ObservedObject<SchemeState>]
    
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
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
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
            
            self.itemList(title: "Reminders", items: self.reminderSchemes, parity: 0)
//
            self.itemList(title: "Upcoming", items: self.upcomingSchemes, parity: 0)
        }
        .padding(.horizontal, 4)
        #if os(macOS)
        .frame(minWidth: 250, maxWidth: 250, maxHeight: .infinity)
        #else
        .frame(minWidth: 250, idealWidth: 250, maxHeight: .infinity)
        #endif
        .padding(.vertical, 8)
        .onAppear {
            self.assignmentSchemesIndices = [:]
            self.upcomingSchemesIndices = [:]
            self.reminderSchemesIndices = [:]
            
            self.actuallyRecomp()
        }
        .onChange(of: schemes.map {$0.wrappedValue}) {
            self.refreshController.scheduleRefresh()
        }
        // names and colors
        .onReceive(Publishers.MergeMany(schemes.map { $0.wrappedValue.objectWillChange })) { _ in
            self.refreshController.scheduleRefresh()
        }
        // adds or removes
        .onReceive(Publishers.MergeMany(schemes.map { $0.wrappedValue.scheme_list.objectWillChange })) { _ in
            self.refreshController.scheduleRefresh()
        }
        // individual schemes
        .onReceive(Publishers.MergeMany(
            schemes.map { $0.wrappedValue.scheme_list.schemes.map { $0.objectWillChange } }.joined()
        )) { _ in
            self.refreshController.scheduleRefresh()
        }
        .onChange(of: refreshController.refreshTrigger) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.actuallyRecomp()
            }
         }
    }
    
    func actuallyRecomp() {
        // theres some swiftui bug with animation
        // so im just making it keep its order as much as possible
        func compare(_ u: SchemeSingularItem, _ v: SchemeSingularItem, _ index: [SchemeSingularItem.IDPath: Int]) -> Bool {
            let ui = index[u.id] ?? Int.max
            let vi = index[v.id] ?? Int.max
            
            if ui != vi {
                return ui < vi
            }
            
            return
                u.state.progress != -1 && v.state.progress == -1 || (u.state.progress != -1) == (v.state.progress != -1) &&
                (u.end ?? u.start)! < (v.end ?? v.start)!
        }
        
        let calendar = NSCalendar.current
        let mainSchemes = schemes.flattenToUpcomingSchemes(start: calendar.startOfDay(for: .now))
        
        self.assignmentSchemes = mainSchemes
            .filter({$0.start == nil && $0.end != nil})
            .sorted { compare($0, $1, self.assignmentSchemesIndices) }
        
        self.assignmentSchemesIndices = [:]
        for (i, a) in self.assignmentSchemes.enumerated() {
            self.assignmentSchemesIndices[a.id] = i
        }
        
        self.reminderSchemes = mainSchemes
            .filter({$0.start != nil && $0.end == nil})
            .sorted { compare($0, $1, self.reminderSchemesIndices) }
        
        self.reminderSchemesIndices = [:]
        for (i, a) in self.reminderSchemes.enumerated() {
            self.reminderSchemesIndices[a.id] = i
        }

        self.upcomingSchemes = mainSchemes
            .filter({$0.start != nil && $0.end != nil && $0.end!.dayDifference(with: .now) == 0})
            .sorted { compare($0, $1, self.upcomingSchemesIndices) }

        self.upcomingSchemesIndices = [:]
        for (i, a) in self.upcomingSchemes.enumerated() {
            self.upcomingSchemesIndices[a.id] = i
        }
    }
}
