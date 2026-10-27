//
//  JellyBoiWidgetExtension.swift
//  JellyBoiWidgetExtension
//
//  Created by Garrett Butchko on 10/20/26.
//

import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct JellyBoiWidgetExtensionEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidgetView
        case .systemMedium:
            mediumWidgetView
        default:
            smallWidgetView
        }
    }

    private var smallWidgetView: some View {
        Link(destination: URL(string: "jellyboi://downloads")!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.indigo.opacity(0.18))
                            .frame(width: 26, height: 39)

                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.indigo)
                    }

                    Spacer()
                }

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    Text("Downloads")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    ProgressView(value: 0.52)
                        .tint(Color.indigo)

                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .medium))
                            Text("Open")
                                .font(.system(size: 11, design: .rounded))
                        }
                        .foregroundStyle(.secondary)

                        Spacer()

                        Text("JellyBoi")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }

    private var mediumWidgetView: some View {
        Link(destination: URL(string: "jellyboi://downloads")!) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(Color.indigo.opacity(0.18))
                        .frame(width: 32, height: 48)

                    Image(systemName: "arrow.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.indigo)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("JellyBoi Downloads")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    ProgressView(value: 0.52)
                        .tint(Color.indigo)

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .medium))

                            Text("Quick Access")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                        }
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                        Spacer()

                        Text("Open")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

struct JellyBoiWidgetExtension: Widget {
    let kind: String = "JellyBoiWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                JellyBoiWidgetExtensionEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                JellyBoiWidgetExtensionEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("JellyBoi Downloads")
        .description("Quick access to your offline media and active downloads.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    JellyBoiWidgetExtension()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .systemMedium) {
    JellyBoiWidgetExtension()
} timeline: {
    SimpleEntry(date: .now)
}
