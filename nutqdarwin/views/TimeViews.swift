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

//struct Block: View {
//    var body: some View {
//        
//    }
//}

struct Time: View {
    @FocusState var focus: Int?
    @State var timeBuffer: String? = ""
    
    @Binding var showing: Bool
    
    @State var date: Date? = .now
    @State var component: Calendar.Component? = .year
    
    
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
            
            date.wrappedValue = newVal
        }
        
        let digits = digitMap[comp]!
        let raw = String(format: "%0\(digits)d", NSCalendar.current.component(comp, from: date.wrappedValue ?? Date.now))
        
        return TextField("", text: Binding(
            get: {
                if let buffer = timeBuffer.wrappedValue, self.focus == fFocus {
                    return buffer
                }
                else {
                    return raw
                }
            }, set: { newValue in
                if self.focus == fFocus {
                    timeBuffer.wrappedValue = String(
                        newValue
                        .filter { $0.isNumber }
                        .suffix(digits)
                    )
                }
            }))
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
                        self.showing = false
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
        }
        .textFieldStyle(.plain)
        .onAppear {
            self.focus = 3
        }
    }
    
    var body: some View {
        self.dateEditor("Start", date: $date, timeBuffer: $timeBuffer, timeComponent: $component)
    }
}

#Preview {
    Time(showing: .constant(true))
}
