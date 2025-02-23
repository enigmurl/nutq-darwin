//
//  nutqdarwin_widget.swift
//  nutqdarwin-widget
//
//  Created by Manu Bhat on 7/4/23.
//

import WidgetKit
import SwiftUI
import Intents

fileprivate let refetchRate: Float = 0.1
fileprivate let updatePeriod = 15 * TimeInterval.minute

struct Provider: IntentTimelineProvider {
    
    fileprivate func getCurrentEntry(_ intent: ConfigurationIntent, completion: @escaping (_ upcoming: UpcomingEntry) -> ()) {
        let env = EnvMiniState()
        
        env.retrieve( { _ in
            let schemes = env.schemes
            
            // not going to write anyways
            // so binding stuff can be kind of iffy
            let flat = schemes.map { ObservedObject(initialValue: $0) }
                .flattenToUpcomingSchemes(start: Date.now)
                
                .filter({$0.start == nil || $0.end == nil || $0.start!.dayDifference(with: .now) == 0}
                )
                .filter { $0.state.progress != -1 }
                .sorted(by: {
                    $0.start ?? $0.end! < $1.start ?? $1.end!
                })
            
            completion(UpcomingEntry(date: .now, configuration: intent, assignments: flat))
        }, allow_online: Float.random(in: 0...1) < refetchRate)
    }
    
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: .now, configuration: ConfigurationIntent(), assignments: [])
    }

    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (UpcomingEntry) -> ()) {
        
        getCurrentEntry(configuration) {
           completion($0)
        }
    }

    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {

        getCurrentEntry(configuration) {
            completion(Timeline(entries: [$0], policy: .after(.now + updatePeriod)))
        }
    }
}


// putting assignments in here makes sense
// but having trouble with sync document loading
struct UpcomingEntry: TimelineEntry {
    var date: Date
    let configuration: ConfigurationIntent
    
    let assignments: [SchemeSingularItem]
}


#warning("TODO, slightly different than pure upcoming, but might want to put in shared anyways")
struct UpcomingAssignmentWidget: View {
    let item: SchemeSingularItem
    
    @Environment(\.widgetFamily) var family
    var isLock: Bool {
#if os(macOS)
        false
#else
        family == .accessoryRectangular
#endif
    }
    
    var color: Color {
        if (item.state.progress == -1) {
            return .gray
        }
        return colorIndexToColor(item.colorIndex)
    }
    
    var dateColor: Color {
        if isLock {
            .white
        }
        else {
            item.widgetDateColor
        }
    }

    var dateString: some View {
        HStack(spacing: 3) {
            if let start = item.start {
                Text(start.dateString.lowercased())
            }
            
            Image(systemName: "arrow.right")
            
            if let end = item.end {
                if self.item.start != nil && end.dayDifference(with: self.item.start!) == 0 {
                    Text(end.timeString)
                }
                else {
                    Text(end.dateString.lowercased())
                }
            }
        }
        .foregroundStyle(self.dateColor)
        .font(.system(size: 10).monospacedDigit())
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if self.isLock {
                    Text(item.text)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                }
                else {
                    Text(item.text)
                        .foregroundStyle(Color.black.opacity(0.8))
                        .font(.system(size: 12))
                        .saturation(0.6)
                        .fontWeight(.semibold)
                }
                self.dateString
                
            }
            .padding(.leading, 6)
            .frame(maxWidth: 155, alignment: .leading)
            .padding(.vertical, 2)
//            .overlay(
//                Rectangle()
//                    .frame(maxWidth: 2.5, alignment: .leading)
//                    .foregroundStyle(.indigo)
//                    .saturation(0.4),
//                alignment: .leading
//            )
            .padding(.trailing, 2)
//            .background(
//                RoundedRectangle(cornerRadius: 5)
//                    .fill(.black.opacity(0.5))
//            )
        }
    }
}

struct UpcomingWidgetView : View {
    @Environment(\.widgetFamily) var family
    
    var entry: UpcomingEntry

    var standard_date: some View {
        HStack(spacing: 2) {
            Spacer()
            
            Text(weekdayFormatter.string(from: .now))
                .foregroundStyle(.red)
            Text(dayOfMonthFormatter.string(from: .now))
                .foregroundStyle(.red)
                .saturation(0.8)
            
            Spacer()
        }
        .font(.system(size: 13).smallCaps())
    }
    
    var isLock: Bool {
#if os(macOS)
        false
#else
        family == .accessoryRectangular
#endif
    }
    
    var date: some View {
        Group {
            if isLock {
                EmptyView()
            }
            else {
                standard_date
            }
        }
    }
    
    fileprivate let columnSize = 3
    
    fileprivate func miniList(_ lst: [SchemeSingularItem]) -> some View {
        VStack(spacing: isLock ? 0 : 6) {
            ForEach(lst) { assignment in
                UpcomingAssignmentWidget(item: assignment)
            }
            
            Spacer()
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            self.date
          
            if self.entry.assignments.count == 0 {
                Spacer()
                Text("No upcoming events")
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            else {
                GeometryReader { proxy in
                    if proxy.size.width > 165 {
                        HStack(alignment: .top) {
                            self.miniList(Array(entry.assignments[0 ..< min(entry.assignments.count, columnSize)]))
                            
                            if entry.assignments.count > columnSize {
                                self.miniList(Array(entry.assignments[columnSize ..< min(entry.assignments.count, columnSize * 2)]))
                            }
                        }
                    }
                    else {
                        self.miniList(Array(entry.assignments[0 ..< min(entry.assignments.count, columnSize)]))
                    }
                }
            }
            
            Spacer()
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
        .containerBackground(.white, for: .widget)
    }
}

struct UpcomingWidget: Widget {
    let kind: String = "upcoming"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Nut Q")
        .description("View your upcoming events, assignments, and reminders.")
#if os(macOS)
        .supportedFamilies([.systemSmall,  .systemMedium])
#else
        .supportedFamilies([.systemSmall,  .systemMedium, .accessoryRectangular])
#endif
        
    }
}

struct NutqWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UpcomingWidgetView(entry: UpcomingEntry(date: .now, configuration: ConfigurationIntent(), assignments: []))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            UpcomingWidgetView(entry: UpcomingEntry(date: .now, configuration: ConfigurationIntent(), assignments: []))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
        .environment(\.colorScheme, .dark)
    }
}
