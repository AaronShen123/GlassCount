import WidgetKit
import SwiftUI

/// Reads the app's state.json (read-only). The app is not sandboxed; the widget is, and is granted a read
/// exception for ~/Library/Application Support/GlassCount/ (see Widget/GlassCountWidget.entitlements).
enum WidgetData {
    static func load() -> (event: CountdownEvent?, count: Int) {
        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return (nil, 0) }
        let url = URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Application Support/GlassCount/state.json")
        guard let data = try? Data(contentsOf: url) else { return (nil, 0) }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let state = try? d.decode(PersistedState.self, from: data) else { return (nil, 0) }
        let now = Date()
        let featured = state.settings.featuredEventID.flatMap { id in state.events.first { $0.id == id } }
            ?? state.events.filter { $0.targetDate > now }.min { $0.targetDate < $1.targetDate }
            ?? state.events.first
        return (featured, state.events.count)
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let event: CountdownEvent?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, event: CountdownEvent(title: "Summer Trip", targetDate: .now.addingTimeInterval(47 * 86_400), iconName: "airplane", colorToken: .teal))
    }
    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : CountdownEntry(date: .now, event: WidgetData.load().event))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let event = WidgetData.load().event
        // Text(.timer) ticks live; an expiry entry also switches the surrounding view's branch.
        let entries = CountdownEngine.refreshDates(from: .now, target: event?.targetDate)
            .map { CountdownEntry(date: $0, event: event) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct GlassCountWidgetView: View {
    let entry: CountdownEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let e = entry.event {
            let b = CountdownEngine.breakdown(from: entry.date, to: e.targetDate)
            VStack(alignment: .leading, spacing: 4) {
                Label(e.title, systemImage: e.iconName).font(.headline).lineLimit(1).foregroundStyle(e.colorToken.color)
                if b.isExpired {
                    Text("It’s here!").font(.title.bold())
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(b.totalDays)").font(.system(size: family == .systemSmall ? 44 : 56, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(b.totalDays == 1 ? "day" : "days").foregroundStyle(.secondary)
                    }
                    .minimumScaleFactor(0.5).lineLimit(1)
                    Text(e.targetDate, style: .timer).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                if family != .systemSmall {
                    Text(e.targetDate.formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "hourglass").font(.title)
                Text("Open GlassCount to add a countdown").font(.caption).multilineTextAlignment(.center)
            }.foregroundStyle(.secondary)
        }
    }
}

struct GlassCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GlassCountWidget", provider: Provider()) { entry in
            GlassCountWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("GlassCount")
        .description("Your featured countdown.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct GlassCountWidgetBundle: WidgetBundle {
    var body: some Widget { GlassCountWidget() }
}
