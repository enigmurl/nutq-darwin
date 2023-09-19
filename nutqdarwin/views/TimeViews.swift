//
//  Time.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 9/5/23.
//

import SwiftUI

fileprivate let digitMap: [Calendar.Component: Int] = [.minute: 2, .hour: 2, .day: 2, .month: 2, .year: 4]
fileprivate let minMap: [Calendar.Component: Int] = [.minute: 0, .hour: 0, .day: 1, .month: 1, .year: 1]
fileprivate let maxMap: [Calendar.Component: Int] = [.minute: 59, .hour: 23, .day: 31, .month: 12, .year: 9999]
#if os(macOS)
fileprivate let digitWidth: CGFloat = 7.5
#else
fileprivate let digitWidth: CGFloat = 11
#endif

fileprivate struct BackgroundView: View {
    let showStroke: Bool
    let radius: CGFloat
   
    init(showStroke: Bool = true, radius: CGFloat = 3) {
        self.showStroke = showStroke
        self.radius = radius
    }
    
    var body: some View {
        ZStack {
            BlurView()
                .opacity(1)
            
            Color.black
                .opacity(0.2)
           
            if showStroke {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.gray, lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(radius: self.radius)
    }
}

fileprivate extension View {
    func blueBackground(padding: CGFloat = 3) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
            }
    }
}

struct Block: View {
    @Environment(\.undoManager) var undo: UndoManager?
    
    @FocusState private var focus: Int?
    @State private var blockBuffer = ""
    @State private var delete = false
    
    @ObservedObject var scheme: SchemeItem
    let menuState: MenuState
    unowned let callback: TreeTextView
    let initial: SchemeRepeat
    let close: () -> ()
    
    func blockEditor(_ label: String, schemeRepeat: Binding<SchemeRepeat>) -> some View {
        let blockBinding = Binding(get: {
            guard case let SchemeRepeat.Block(block) = schemeRepeat.wrappedValue else {
                return SchemeRepeat.BlockRepeat()
            }
            
            return block
        }, set: { (val: SchemeRepeat.BlockRepeat) in
            
            /* ensure state is proper */
            let target = val.remainders.count * val.blocks
            if self.scheme.state.count > target {
                self.scheme.state.removeLast(self.scheme.state.count - target)
            }
            else if self.scheme.state.count < target {
                self.scheme.state.append(contentsOf: [SchemeSingularState](repeating: SchemeSingularState(), count: target - self.scheme.state.count))
            }
            
            if !delete {
                schemeRepeat.wrappedValue = .Block(block: val)
            }
            /* autocompletion of events may be slightly lagged, but generally it's fine */
        })
        
        return (
            HStack(spacing: 4) {
                #if os(macOS)
                Text(label)
                    .font(.body.bold())
                    .padding(.trailing, 4)
                #endif
                
                Text("rem")
                TextField("", text: Binding(get: {
                    blockBuffer
                }, set: { str in
                    blockBuffer = str.filter {$0.isNumber || $0 == ","}
                    blockBinding.wrappedValue.remainders = blockBuffer
                        .split(separator: ",")
                        .map { Int($0) ?? 0 }
                }))
                    .focused($focus, equals: 1)
                    .frame(maxWidth: 60)
                    .blueBackground()
                    .padding(.trailing, 4)
                    .onSubmit {
                        focus = 2
                    }
                
                Text("blocks")
                TextField("", text: Binding(digits: blockBinding.blocks, min: 1, max: SchemeRepeat.BlockRepeat.maxBlocks))
                    .focused($focus, equals: 2)
                    .frame(maxWidth: 20)
                    .blueBackground()
                    .padding(.trailing, 4)
                    .onSubmit {
                        self.focus = 3
                    }
                
                Text("mod")
                TextField("", text: Binding(digits: blockBinding.modulus, min: 1))
                    .focused($focus, equals: 3)
                    .frame(maxWidth: 20)
                    .blueBackground()
                    .padding(.trailing, 2)
                    .onSubmit {
                        focus = 0
                        close()
                    }

                Text("(days)")
                    .font(.caption2.lowercaseSmallCaps())
                
                Image(systemName: "minus.square")
                    .onTapGesture {
                        self.scheme.state = [scheme.state.first ?? SchemeSingularState()]
                        self.scheme.repeats = .None
                        
                        delete = true
                        
                        close()
                    }
#if os(macOS)
                .buttonStyle(.link)
#endif
                .foregroundStyle(.red)
                
            }
#if os(macOS)
            .focusSection()
#endif
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .onAppear {
                DispatchQueue.main.async {
                    self.focus = 1
                }
                
                blockBuffer = blockBinding.wrappedValue.remainders
                    .map { String($0)}
                    .joined(separator: ",")
                
            }
            .onDisappear {
                // not necessary (or guaranteed to be called), but generally useful
                if !delete {
                    blockBinding.wrappedValue.remainders = Array(Set(
                        blockBuffer
                            .split(separator: ",")
                            .map { min(blockBinding.wrappedValue.modulus - 1, max(Int($0) ?? 0, 0)) }
                    )).sorted()
                }
            }
        )
    }
    
    @State var hasPassedInit = false
    
    var body: some View {
        VStack {
            self.blockEditor("Block Repeat", schemeRepeat: $scheme.repeats)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            BackgroundView()
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(menuState) {
            if hasPassedInit {
                self.callback.handle(action: $0, publisher: menuState)
            }
            else {
                hasPassedInit = true
            }
        }
        .onDisappear {
            callback.setBinding($scheme.repeats, old: initial, new: scheme.repeats)
        }
    }
}

struct Time: View {
    @FocusState private var focus: Int?
    @State private var timeBuffer: String? = ""
    @State private var component: Calendar.Component? = .year
    
    @State var updater = 0
   
    let label: String
    @Binding var date: Date?
    @Binding var state: [SchemeSingularState]
    let menuState: MenuState
    unowned let callback: TreeTextView
    let initial: Date?
    let close: () -> ()
    
    func reallySet(_ comp: Calendar.Component, value: Int, date: Date) -> Date {
        var components = NSCalendar.current.dateComponents([.minute, .hour, .day, .month, .year], from: date)
        components.setValue(value, for: comp)
        return NSCalendar.current.date(from: components)!
    }
    
    func field(date: Binding<Date?>, timeBuffer: Binding<String?>, timeComponent: Binding<Calendar.Component?>, fFocus: Int, delFocus: Int = 1, comp: Calendar.Component) -> some View {
        func write(comp: Calendar.Component?) {
            guard let comp = comp, let timeBuffer = timeBuffer.wrappedValue, let dateVal = date.wrappedValue else {
                return
            }
            
            let mn = minMap[comp]!
            let mx = maxMap[comp]!
            
            let oldComponent = NSCalendar.current.component(comp, from: dateVal)
            let clipped = timeBuffer.filter {$0.isNumber}
            let newComponent = min(mx, max(mn, Int(clipped) ?? mn))
            
            // has 31 days in march
            let reference = reallySet(comp, value: oldComponent, date: referenceDate)
            let newReference = reallySet(comp, value: newComponent, date: referenceDate)
            
            var newVal: Date = dateVal + newReference.timeIntervalSince(reference)
            
            // kind of hacky, but relaisitcally when you change month you want date to reset sooo
            if comp == .month && newComponent != oldComponent {
                newVal = reallySet(.day, value: 1, date: newVal)
                newVal = reallySet(.month, value: newComponent, date: newVal)
            }
            else if comp == .year && newComponent != oldComponent {
                newVal = reallySet(.day, value: 1, date: newVal)
                newVal = reallySet(.month, value: 1, date: newVal)
                newVal = reallySet(.year, value: newComponent, date: newVal)
            }
            else if comp == .hour && newComponent != oldComponent {
                newVal = reallySet(.minute, value: 0, date: newVal)
                newVal = reallySet(.hour, value: newComponent, date: newVal)
            }
            
            newVal = reallySet(.second, value: 0, date: newVal)
            
            if newVal != date.wrappedValue {
                date.wrappedValue = newVal
                
                for item in $state {
                    item.wrappedValue.progress = 0
                    item.wrappedValue.delay = 0
                }
            }
            
        }
        
        let digits = digitMap[comp]!
        let raw = String(format: "%0\(digits)d", NSCalendar.current.component(comp, from: date.wrappedValue ?? Date.now))
        
        return TextField("", text: Binding(
            get: {
                if let buffer = timeBuffer.wrappedValue, self.focus == fFocus, timeComponent.wrappedValue == comp {
                    return buffer
                }
                else {
                    return raw
                }
            }, set: { newValue in
                if self.focus == fFocus && timeComponent.wrappedValue == comp {
                    timeBuffer.wrappedValue = String(
                        newValue
                        .filter { $0.isNumber }
                        .suffix(digits)
                    )
                }
            }))
        .tint(.red)
        .multilineTextAlignment(.trailing)
#if os(iOS)
        .keyboardType(.numbersAndPunctuation)
#endif
        .focused(self.$focus, equals: fFocus)
        .frame(maxWidth: CGFloat(digits) * digitWidth)
        .onAppear {
            timeComponent.wrappedValue = nil
        }
        .onChange(of: self.focus, initial: true) { focus, mf in
            if focus == fFocus {
                // absolute state...
                write(comp: timeComponent.wrappedValue)
            }
            if mf == fFocus {
                write(comp: timeComponent.wrappedValue)
                // NOTE: cannot be cached with other string
                // since may have changed as result of write
                let current = String(format: "%0\(digits)d", NSCalendar.current.component(comp, from: date.wrappedValue ?? Date.now))
                timeBuffer.wrappedValue = current
                timeComponent.wrappedValue = comp
            }
            else if mf == nil {
                timeBuffer.wrappedValue = nil
                timeComponent.wrappedValue = nil
            }
        }
        .onDisappear {
            if let comp = timeComponent.wrappedValue {
                write(comp: comp)
            }
            timeComponent.wrappedValue = nil
            timeBuffer.wrappedValue = nil
        }
        .onSubmit {
            write(comp: comp)
            
            self.focus = fFocus + delFocus
            
            // reset
            if fFocus + delFocus == 0 {
                close()
            }
        }
    }
    
    func dateEditor(_ label: String, date: Binding<Date?>, timeBuffer: Binding<String?>, timeComponent: Binding<Calendar.Component?>) -> some View {
        HStack {
#if os(macOS)
            Text(label)
                .font(.body.bold())
#endif
            
            HStack(spacing: 0) {
                //YYYY
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, fFocus: 1, comp: .year)
                Text("/")
                    .padding(.leading, 2)
                
                //MM
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, fFocus: 2, comp: .month)
                Text("/")
                    .padding(.leading, 2)
                
                //DD
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, fFocus: 3, comp: .day)
            }
            .monospaced()
            .blueBackground()
            
            Text("at")
            
            HStack(spacing: 0) {
                //HH
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, fFocus: 4, comp: .hour)
                Text(":")
                
                //MM
                self.field(date: date, timeBuffer: timeBuffer, timeComponent: timeComponent, fFocus: 5, delFocus: -5, comp: .minute)
            }
            .monospaced()
            .blueBackground()
            
           
            // cant do buttons because of our scuffed hitTest method
            Image(systemName: "minus.square")
                .onTapGesture {
                    close()
                    self.date = nil
                }
            
#if os(macOS)
            .buttonStyle(.link)
#endif
            .foregroundStyle(.red)
        }
        .textFieldStyle(.plain)
        .onAppear {
            self.focus = 3
        }
    }
    
    var calendar: some View {
        let date = self.date!
        let calendar = Calendar.current
      
        let currentDay = calendar.dateComponents([.year, .month], from: date) == calendar.dateComponents([.year, .month], from: .now) ? calendar.component(.day, from: .now) : -1
        
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) - 1
        let targetDayOfMonth = calendar.component(.day, from: date)
        let days = calendar.range(of: .day, in: .month, for: date)!
    
        var weeks: [[Int]] = [[]]
        for day in days {
            let weekDay = (firstWeekday + day - 1) % 7
            
            weeks[weeks.count - 1].append(day)
            
            if weekDay == 6 && day != days.last {
                weeks.append([])
            }
        }
        
        if weeks[0].count < 7 {
            weeks[0].insert(contentsOf: Array(stride(from: -1, through: weeks[0].count - 7, by: -1)), at: 0)
        }
        
        if weeks[weeks.count - 1].count < 7 {
            weeks[weeks.count - 1].append(contentsOf: Array(stride(from: -8, through: weeks[weeks.count - 1].count - 14, by: -1)))
        }
        
        return (
            Grid {
                ForEach(weeks, id: \.self) { week in
                    GridRow {
                        ForEach(week, id: \.self) { day in
                            Button {
                                if day > 0 {
                                    if focus == 3 {
                                        timeBuffer = String(format: "%02d", day)
                                    }
                                    
                                    self.date = firstDayOfMonth + TimeInterval(day - 1) * .day
                                }
                            } label: {
                                Group {
                                    if day > 0 {
                                        Text("\(day)")
                                            .bold(day == targetDayOfMonth)
                                            .foregroundStyle(day == currentDay && day != targetDayOfMonth ? Color.red : Color.primary)
                                    }
                                    else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 25, height: 25)
                                .background {
                                    if day == targetDayOfMonth {
                                        Circle()
                                            .fill(Color.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .allowsHitTesting(true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        )
    }
   
    @State var hasPassedInit = false
    
    var body: some View {
        VStack {
            if self.date != nil {
                self.dateEditor(self.label, date: $date, timeBuffer: $timeBuffer, timeComponent: $component)
                
                self.calendar
            }
        }
        .padding(6)
        .background {
            BackgroundView()
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(menuState) {
            if hasPassedInit {
                self.callback.handle(action: $0, publisher: menuState)
            }
            else {
                hasPassedInit = true
            }
        }
        .onDisappear {
            callback.setBinding($date, old: initial, new: date)
        }
    }
}
