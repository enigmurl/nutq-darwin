//
//  Calendar.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 6/14/23.
//

import SwiftUI
import Combine
#if os(macOS)
import Cocoa
#endif

fileprivate let hourHeight: CGFloat = 40
fileprivate let timeLegendWidth: CGFloat = 50
fileprivate let timeLegendYOffset: CGFloat = 12

struct TimeLegend: View {
    let proxy: ScrollViewProxy
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 24) { i in
                Text(String(format: "%02d:00", i))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.gray)
                    .frame(width: 35, height: hourHeight, alignment: .topTrailing)
                    .padding(.horizontal, 4)
            }
            Color.clear
                .frame(height: 0)
                .id(0)
                .onAppear {
                    proxy.scrollTo(0, anchor: .bottom)
                }
        }
        .frame(width: timeLegendWidth)
    }
}


struct DayHeader: View {
    let index: Int
    let date: Date
    
    var dayOfMonth: Int {
        NSCalendar.current.component(.day, from: self.date)
    }
    
    var dayOfWeek: Int {
        NSCalendar.current.component(.weekday, from: self.date)
    }
    
    var month: String {
        return monthFormatter.string(from: self.date)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if index == 0 || dayOfMonth == 1 {
                Text(month)
                    .fontWeight(.heavy)
                    .saturation(0.7)
            }
            else {
                Text(daysOfWeek[dayOfWeek - 1])
            }

            Text(String(dayOfMonth))
        }
        .foregroundStyle(date.dayDifference(with: .now) != 0 ? Color.primary : Color.red)
        .font(.title3)
        .frame(maxWidth: .infinity, minHeight: hourHeight - 1, maxHeight: hourHeight - 1) /* for divider */
    }
}

struct CalendarHeader: View {
    let days: [Date]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                /* alignment */
                Color.clear
                    .font(.largeTitle.bold())
                    .frame(minWidth: timeLegendWidth, maxWidth: timeLegendWidth)
                
                ForEach(Array(days.enumerated()), id: \.element) { i, day in
                    DayHeader(index: i, date: day)
                }
            }
            Divider()
        }
        .frame(minHeight: hourHeight, maxHeight: hourHeight)
    }
}

#warning("TODO coordinate compression so we don't always have them in different columns whenever necessary")
struct CalendarEvents: View {
    // array of intersections
    // each intersection is an array of duplicates (duplicates are same time/same type) events)
    // each duplicate is an array of single iterms
    let day: Date
    let mergedEvents: [[[SchemeSingularItem]]]
    let schemes: [SchemeSingularItem]
        
    /* not perfect, but does an ok job usually */
    init(day: Date, schemes: [SchemeSingularItem]) {
        self.day = day
        self.schemes = schemes
        
        if schemes.count == 0 {
            mergedEvents = []
            return
        }
        
        let timeSorted = schemes.sorted(by: {
            let time1 = $0.start ?? $0.end! - .hour
            let time2 = $1.start ?? $1.end! - .hour
            return time1 < time2 || time1 == time2 && $0.schemeType.rawValue < $1.schemeType.rawValue
        })
        
        var partition: [[SchemeSingularItem]] = []
        var running: [SchemeSingularItem] = [timeSorted[0]]
        for item in timeSorted.dropFirst() {
            if item.schemeType != running[0].schemeType || item.start != running[0].start || item.end != running[0].end {
                partition.append(running)
                running = [item]
            }
            else {
                running.append(item)
            }
        }
        partition.append(running)
        
        // first do single merging
        // then see if any events would intersect, and collapse
        var intersections: [[[SchemeSingularItem]]] = []
        var interRunning: [[SchemeSingularItem]] = [partition[0]]
        for group in partition.dropFirst() {
            //default height of events and assignments are 1 hour
            let oldEnd = interRunning.last![0].end ?? interRunning.last![0].start! + .hour
            let newStart = group[0].start ?? group[0].end! - .hour
            if newStart > oldEnd {
                intersections.append(interRunning)
                interRunning = [group]
            }
            else {
                interRunning.append(group)
            }
        }
        intersections.append(interRunning)
        
        
        self.mergedEvents = intersections
    }
    
    private func dateString(start: Date?, end: Date?) -> String {
        if start != nil && end != nil {
            let s = hourFormatter.string(from: start!)
            let e = hourFormatter.string(from: end!)
            return "\(s) to \(e)"
        }
        else if start != nil {
            let s = hourFormatter.string(from: start!)
            return "At \(s)"
        }
        else {
            let e = hourFormatter.string(from: end!)
            return "Due \(e)"
        }
    }
    
    var body: some View {
        /* merging protocol
           if different time or different event, then display horizontally
           if same time and same same type of event, then display inline
                if so, if different colors, display white, otherwise display the same color, works?
         */
        ForEach(mergedEvents, id: \.first!.first!.id) { intersection in
            HStack(spacing: 2) {
                ForEach(intersection, id: \.first!.id) { duplicates in
                    let head = duplicates[0]
                    let above: CGFloat = head.start == nil ? 0 : hourHeight * min(23, head.start!.timeIntervalSince(day.startOfDay()) / .hour)
                    let minCurr: CGFloat = head.start == nil || head.end == nil ? 0 : hourHeight * head.end!.timeIntervalSince(head.start!) / .hour
                    let effectiveTime = head.start == nil || head.end == nil ? 1: head.end!.timeIntervalSince(head.start!)
                    let below: CGFloat = head.end == nil ? 0 : hourHeight * min(23, (24.0 - head.end!.timeIntervalSince(day.startOfDay()) / .hour))
                    
                    VStack {
                        Text(self.dateString(start: head.start, end: head.end))
                            .font(.caption.monospaced())
                            .padding(.top, 3)
                            .padding(.leading, 6)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        
                        ForEach(duplicates, id: \.id) { item in
                            /* display */
                            Text(item.text)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(colorIndexToColor(item.colorIndex))
                                .saturation(item.state.progress == -1 ? 0 : 0.7)
                                .font(Font.system(size: 12).bold())
                                .padding(.horizontal, 6)
                                .lineLimit(effectiveTime > .hour ? 2 : 1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.bottom, 5)
                    .background(alignment: .top) {
                        if head.start == nil || head.end == nil {
                            Rectangle()
                                .foregroundStyle(.white.opacity(0.2))
                            GeometryReader { shape in
                                Path { path in
                                    let w = shape.size.width
                                    let h = shape.size.height
                                    
                                    if head.start != nil {
                                        path.move(to: .zero)
                                        path.addLine(to: CGPoint(x: w, y: 0))
                                    }
                                    else if head.end != nil {
                                        path.move(to: CGPoint(x: 0, y: h))
                                        path.addLine(to: CGPoint(x: w, y: h))
                                    }
                                }
                                .stroke(.white, lineWidth: 2)
                            }
                        }
                        else {
                            Group {
                                RoundedRectangle(cornerRadius: 3)
                                    .foregroundStyle(.white.opacity(0.2))
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(.white, lineWidth: 2)
                            }
                            .padding(2)
                            .frame(minHeight: minCurr)
                        }
                    }
                    .padding(head.start == nil ? .bottom : .top,
                             max(0, head.start == nil ? below : above))
                    .frame(maxHeight: .infinity, alignment: head.start == nil ? .bottom : .top)
                }
            }
        }
    }
}

struct CalendarDay: View {
    @EnvironmentObject var env: EnvState
    
    let day: Date
    let schemes: [SchemeSingularItem]
    let isActive: Bool
    let isWeekend: Bool

    var filledPixels: CGFloat {
        let now = env.stdTime
        
        if day > now {
            return 0
        }
        var ret: CGFloat = timeLegendYOffset
        if day.dayDifference(with: now) == 0 {
            ret += hourHeight * now.timeIntervalSince(day.startOfDay()) / TimeInterval.hour
        }
        else {
            ret += 24 * hourHeight
        }
        
        return ret
    }
    
    var filteredSchemes: [SchemeSingularItem] {
        schemes.filter({
            $0.start != nil && $0.start!.dayDifference(with: day) == 0 ||
            $0.end != nil && $0.end!.dayDifference(with: day) == 0
        })
    }
    
    var events: some View {
        CalendarEvents(day: day, schemes: filteredSchemes)
    }
    
    var completedDateOpacity: CGFloat {
        #if os(macOS)
        0.075
        #else
        0.15
        #endif
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(0 ..< 24) { i in
                    VStack(spacing: 0) {
                        Divider()
                        Spacer()
                    }
                    .frame(height: hourHeight)
                }
            }
            
            self.events
                .padding(.horizontal, 1)
        }
        .padding(.top, timeLegendYOffset)
        .overlay(
            Color.blue.opacity(completedDateOpacity)
                .frame(height: filledPixels, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
        )
        .overlay(alignment: .top) {
            if day.dayDifference(with: .now) == 0 {
                ZStack(alignment: .leading) {
                    Circle()
                        .frame(width: 10, height: 10)
                        .offset(x: -5)
                    Rectangle()
                        .frame(height: 2)
                }
                    .foregroundStyle(.red)
                    .padding(.top, filledPixels - 6) // accounts for circle height
            }
        }

    }
}

struct CalendarView: View {
    @EnvironmentObject var env: EnvState
    
    let schemes: [ObservedObject<SchemeState>]
    @State var headDate = Date.now
    
    var body: some View {
        GeometryReader { proxy in
            if env.scheme == unionNullUUID {
                VStack(spacing: 0) {
                    let count = dayCount(for: proxy.size.width)
                    let days = self.days(count: count)
                    let schemes = self.schemes.flattenEventsInRange(start: days[0].startOfDay(), end: days.last!.startOfDay() + TimeInterval.day, schemeTypes: [.assignment, .event, .reminder])
                    
                    CalendarHeader(days: days)
                    
                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            HStack(spacing: 0) {
                                TimeLegend(proxy: scrollProxy)
                                
                                ForEach(days, id: \.self) { day in
                                    Divider()
                                    CalendarDay(day: day, schemes: schemes, isActive: false, isWeekend: true)
                                }
                            }
                        }
#if os(macOS)
                        .overlay(SwipeViewRepresentable(date: $headDate, displayedDates: count))
#else
                        .simultaneousGesture(DragGesture()
                            .onEnded { gesture in
                                guard abs(gesture.translation.width) > abs(gesture.translation.height) else {
                                    return
                                }
                                
                                if gesture.translation.width < 0 {
                                    withAnimation {
                                        self.headDate = self.headDate + Double(count) * TimeInterval.day
                                    }
                                }
                                else {
                                    withAnimation {
                                        self.headDate = self.headDate - Double(count) * TimeInterval.day
                                    }
                                }
                            }
                        )
#endif
                        
                    }
                }
            }
                
        }
        #if os(macOS)
        .frame(minWidth: 825, maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
    
    private func dayCount(for width: CGFloat) -> Int {
        /* mobile */
        if width < 400 {
            return 1
        }
        else {
            return min(7, Int(width / 120))
        }
    }
    
    private func days(count: Int) -> [Date] {
        // if 7, do entire week
        // otherwise do
        let offset: Int
        if count == 7 {
            offset = NSCalendar.current.component(.weekday, from: self.headDate) - 1
        }
        else {
            offset = count / 2
        }
        
        return Array(-offset ..< count - offset).map({self.headDate + Double($0) * TimeInterval.day})
    }
}

#if os(macOS)
struct SwipeViewRepresentable: NSViewRepresentable {
    @Binding var date: Date
    var displayedDates: Int

    func makeNSView(context: NSViewRepresentableContext<Self>) -> MacosSwipeRecognizer {
        let swipeView = MacosSwipeRecognizer()
        swipeView.wantsLayer = true
        swipeView.layer?.backgroundColor = NSColor.clear.cgColor
        return swipeView
    }
    
    func updateNSView(_ nsView: MacosSwipeRecognizer, context: NSViewRepresentableContext<Self>) {
        nsView.date = $date
        nsView.displayedDates = displayedDates
    }
}

#warning("TODO, see if there's a native solution...")
class MacosSwipeRecognizer: NSView {
    var date: Binding<Date>!
    var displayedDates: Int = 0
    
    private var start: Date?
    private var cumulativeScroll: CGFloat = 0
    
    override var acceptsFirstResponder: Bool {
        true
    }
    
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began {
            start = Date.now
            cumulativeScroll = 0
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                self.window?.makeFirstResponder(self)
            }
        }
        else if event.phase == .ended && self.window?.firstResponder == self {
            let duration = Date.now.timeIntervalSince(start!)
           
            if duration < 0.2 && abs(cumulativeScroll) > 100 {
                if cumulativeScroll < 0 {
                    withAnimation {
                        date.wrappedValue = date.wrappedValue + Double(displayedDates) * TimeInterval.day
                    }
                }
                else {
                    withAnimation {
                        date.wrappedValue = date.wrappedValue - Double(displayedDates) * TimeInterval.day
                    }
                }
                
                NSApp.sendAction(#selector(NSView.resignFirstResponder), to: nil, from: self)
            }
        }
        
        cumulativeScroll += event.scrollingDeltaX
        
        super.scrollWheel(with: event)
    }
}
#endif
