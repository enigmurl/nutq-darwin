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


typealias SchemeChunk = (equalGroups: [[SchemeSingularItem]], showTime: Bool, offset: Double)
fileprivate let overlapOffset = 15.0
fileprivate let baseHeightHours = 0.125
fileprivate let runLineHours = 0.4
fileprivate let timeHeaderHours = 0.3

#warning("TODO coordinate compression so we don't always have them in different columns whenever necessary")
struct CalendarEvents: View {
    // array of intersections
    // each intersection is an array of duplicates (duplicates are same time/same type) events)
    // each duplicate is an array of single iterms
    let day: Date
    var mergedEvents: [[SchemeChunk]]
    
    let schemes: [SchemeSingularItem]
    
        
    /* not perfect, but does an ok job usually */
    init(day: Date, schemes: [SchemeSingularItem]) {
        self.day = day
        self.schemes = schemes
        
        self.mergedEvents = []
        for t in [SchemeType.event, SchemeType.reminder, SchemeType.assignment] {
            let timeSorted = schemes
                .filter { $0.schemeType == t }
                .sorted {
                    if t == .event {
                        return $0.start! < $1.start! || $0.start == $1.start && $0.end! < $1.end!
                    }
                    else {
                        let time1 = $0.start ?? $0.end!
                        let time2 = $1.start ?? $1.end!
                        return time1 < time2
                    }
                }
            
            if timeSorted.isEmpty {
                self.mergedEvents.append([])
                continue
            }
            
            var partition: [[SchemeSingularItem]] = []
            var running: [SchemeSingularItem] = [timeSorted[0]]
            for item in timeSorted.dropFirst() {
                if item.start != running[0].start || item.end != running[0].end {
                    partition.append(running)
                    running = [item]
                }
                else {
                    running.append(item)
                }
            }
            partition.append(running)
            
            
            
            func convertIntersection(equalGroups: [[SchemeSingularItem]]) -> SchemeChunk {
                if self.mergedEvents.isEmpty {
                    return (equalGroups: interRunning, showTime: true, offset: Double(0.0))
                }
                
                let effectiveRange = estimateRange(items: equalGroups, showTime: true, onlyVisual: true)
                let effectiveClippedRange = estimateRange(items: equalGroups, showTime: false, onlyVisual: true)
                
                var showTime = true
                var offset = 0.0
                for group in self.mergedEvents {
                    for chunk in group {
                        let range = estimateRange(items: chunk.equalGroups, showTime: chunk.showTime, onlyVisual: true)
                        if effectiveRange.overlaps(range) {
                            if effectiveClippedRange.overlaps(range) {
                                offset = max(offset, chunk.offset + overlapOffset)
                                showTime = false
                            }
                            else {
                                showTime = false
                            }
                        }
                    }
                }
                
                return (equalGroups: interRunning, showTime: showTime, offset: offset)
            }
            
            // first do single merging
            // then see if any events would intersect, and collapse
            var intersections: [SchemeChunk] = []
            var interRunning: [[SchemeSingularItem]] = [partition[0]]
            for group in partition.dropFirst() {
                // heuristic height estimate
                let oldEnd = estimateRange(items: interRunning, showTime: true, onlyVisual: false)
                    .upperBound
                
                let newStart = estimateRange(items: [group], showTime: true, onlyVisual: false).lowerBound
                if newStart >= oldEnd {
                    // convert to a scheme chunk
                    intersections.append(convertIntersection(equalGroups: interRunning))
                    interRunning = [group]
                }
                else {
                    interRunning.append(group)
                }
            }
            intersections.append(convertIntersection(equalGroups: interRunning))
            
            
            self.mergedEvents.append(intersections)
        }
    }
    
    private func estimateRange(items: [[SchemeSingularItem]], showTime: Bool, onlyVisual: Bool) -> Range<Date> {
        
        var increase = baseHeightHours * TimeInterval.hour
        for group in items {
            if showTime {
                increase += timeHeaderHours * TimeInterval.hour
            }
            increase += runLineHours * Double(group.count) * .hour
        }
        
        if items[0][0].schemeType == .event {
            let lower = items.map { $0[0].start! }.min()!
            
            let upper: Date
            if onlyVisual {
                upper = lower + increase
            }
            else {
                upper = max(lower + increase, items.map { $0[0].end! }.max()!)
            }
            
            return lower ..< upper
        }
        else if items[0][0].schemeType == .assignment {
            let upper = items.last![0].end!

            let lower = upper - increase
            return lower ..< upper
        }
        else {
            /* reminder */
            let lower = items[0][0].start!
            let upper = lower + increase
            
            return lower ..< upper
        }
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
    
    private func chunk(_ chunk: SchemeChunk) -> some View {
        let head = chunk.equalGroups.first![0]
        let tail = chunk.equalGroups.last![0]
        
        let above: CGFloat = head.start == nil ? 0 : hourHeight * min(23, head.start!.timeIntervalSince(day.startOfDay()) / .hour)
        let minCurr: CGFloat = head.start == nil || tail.end == nil ? 0 : hourHeight * tail.end!.timeIntervalSince(head.start!) / .hour
        let below: CGFloat = tail.end == nil ? 0 : hourHeight * min(23, (24.0 - tail.end!.timeIntervalSince(day.startOfDay()) / .hour))
        
        let hideTime = head.schemeType == .event && tail.end!.timeIntervalSince(head.start!) <= 30 * TimeInterval.minute || !chunk.showTime
        
        var extraLines = 0
        if head.schemeType == .event {
            let totalTime = tail.end!.timeIntervalSince(tail.start!)
            var usingOnes = baseHeightHours * TimeInterval.hour
            for group in chunk.equalGroups {
                if chunk.showTime {
                    usingOnes += timeHeaderHours * TimeInterval.hour
                }
                usingOnes += runLineHours * Double(group.count) * TimeInterval.hour
            }
            extraLines = max(0, Int((totalTime - usingOnes) / (runLineHours * 0.95 * TimeInterval.hour)))
        }
        
        var lineMap: [Int] = []
        for group in chunk.equalGroups {
            lineMap.append(extraLines >= group.count ? 2 : 1)
            extraLines -= group.count
        }
        
        return VStack(spacing: 0) {
            ForEach(Array(zip(chunk.equalGroups, lineMap)), id: \.0.first!.id) { (items, lines) in
                if !hideTime {
                    Text(self.dateString(start: items[0].start, end: items[0].end))
                        .font(.caption.monospaced())
                        .scaleEffect(CGSize(width: 0.8, height: 0.8))
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                
                ForEach(items, id: \.id) { item in
                    Text(item.text)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(colorIndexToColor(item.colorIndex))
                        .saturation(item.state.progress == -1 ? 0 : 0.7)
                        .font(Font.system(size: 10).bold())
                        .padding(.horizontal, 6)
                        .lineLimit(lines)
                        .truncationMode(.tail)
                }
                .padding(.top, hideTime ? 3 : 0)
            }
        }
        .padding(.top, 3)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            if head.schemeType != .event {
                if chunk.offset != 0 {
                    Rectangle()
                        .foregroundStyle(.ultraThickMaterial.opacity(0.6))
                        .blur(radius: 4)
                }
                else {
                    Rectangle()
                        .foregroundStyle(Color.white.opacity(0.1))
                }
                
                GeometryReader { shape in
                    Path { path in
                        let w = shape.size.width
                        let h = shape.size.height
                        
                        if head.start != nil {
                            path.move(to: .zero)
                            path.addLine(to: CGPoint(x: w, y: 0))
                        }
                        else if tail.end != nil {
                            path.move(to: CGPoint(x: 0, y: h))
                            path.addLine(to: CGPoint(x: w, y: h))
                        }
                    }
                    .stroke(.white, lineWidth: 1.5)
                }
            }
            else {
                Group {
                    RoundedRectangle(cornerRadius: 3)
                        .foregroundStyle(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.white, lineWidth: 1.5)
                }
                .padding(2)
                .frame(minHeight: minCurr)
            }
        }
        .padding(head.start == nil ? .bottom : .top,
                 max(0, head.start == nil ? below : above))
        .padding(.leading, chunk.offset)
        .frame(maxHeight: .infinity, alignment: head.start == nil ? .bottom : .top)
        
    }
    
    var body: some View {
        /* merging protocol
           if different time or different event, then display horizontally
           if same time and same same type of event, then display inline
                if so, if different colors, display white, otherwise display the same color, works?
         */
        Group {
            ForEach(mergedEvents[0], id: \.equalGroups.first!.first!.id) { intersection in
                self.chunk(intersection)
            }
            ForEach(mergedEvents[1], id: \.equalGroups.first!.first!.id) { intersection in
                self.chunk(intersection)
            }
            ForEach(mergedEvents[2], id: \.equalGroups.first!.first!.id) { intersection in
                self.chunk(intersection)
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
        .background {
            if self.isWeekend {
                Color.gray.opacity(0.1)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
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
                                    CalendarDay(day: day, schemes: schemes, isActive: false, isWeekend: Calendar.current.isDateInWeekend(day))
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
        return Array(0 ..< count).map({self.headDate + Double($0) * TimeInterval.day})
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
        else if event.phase == .ended && self.window?.firstResponder == self && start != nil {
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
