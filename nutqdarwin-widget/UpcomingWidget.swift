//
//  nutqdarwin_widget.swift
//  nutqdarwin-widget
//
//  Created by Manu Bhat on 7/4/23.
//

import WidgetKit
import SwiftUI
import Intents

#if DEBUG
fileprivate let updatePeriod: TimeInterval = .minute
#else
fileprivate let updatePeriod = 15 * TimeInterval.minute
#endif

struct Provider: IntentTimelineProvider {
    
    fileprivate func getCurrentEntry(_ intent: ConfigurationIntent, completion: @escaping (_ upcoming: UpcomingEntry) -> ()) {
        let _ = EnvMiniState { env in
            var schemes = env.schemes
            
            // not going to write anyways
            // so binding stuff can be kind of iffy
            let flat = Array(0 ..< schemes.count)
                .map { i in
                    Binding(get: {
                        schemes[i]
                    }, set: {
                        schemes[i] = $0
                    })
                }
                .flattenToUpcomingSchemes(start: Date.now)
                .sorted(by: {
                    $0.start ?? $0.end! < $1.start ?? $1.end!
                })
            
            completion(UpcomingEntry(date: .now, configuration: intent, assignments: flat))
        }
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
    
    var color: Color {
        if (item.state == -1) {
            return .gray
        }
        return colorIndexToColor(item.colorIndex)
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
        .foregroundColor(self.item.dateColor)
        .font(.system(size: 10).monospacedDigit())
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                self.dateString
                Text(item.text)
                    .font(.system(size: 14))
            }
            .padding(.leading, 6)

            Spacer()
        }
        .overlay(
            Rectangle()
                .frame(maxWidth: 1.5, alignment: .leading)
                .foregroundColor(color)
                .saturation(0.4),
            alignment: .leading
        )
    }
}

struct UpcomingWidgetView : View {
    var entry: UpcomingEntry

    var date: some View {
        HStack {
            Text(weekdayFormatter.string(from: .now))
                .foregroundColor(.red)
            Text(dayFormatter.string(from: .now))
                .foregroundColor(.blue)
                .saturation(0.8)
            Spacer()
        }
        .font(.system(size: 13).smallCaps())
    }
    
    fileprivate let columnSize = 3
    
    fileprivate func miniList(_ lst: [SchemeSingularItem]) -> some View {
        VStack(spacing: 6) {
            ForEach(lst) { assignment in
                UpcomingAssignmentWidget(item: assignment)
            }
            
            Spacer()
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            self.date
                .padding([.horizontal, .top], 12)
           
            
            GeometryReader { proxy in
                if proxy.size.width > 165 {
                    HStack {
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
            .padding(.leading, 12)
            
            Spacer()
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
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
        .supportedFamilies([.systemSmall, .systemMedium])
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
