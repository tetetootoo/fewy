import SwiftUI
import WidgetKit

struct NotesEntry: TimelineEntry {
    let date: Date
    let notes: [Note]
}

struct NotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesEntry {
        NotesEntry(date: .now, notes: [Note(text: "Catch a little thought.")])
    }
    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }
    private func entry() -> NotesEntry {
        NotesEntry(date: .now, notes: Array(Notes.load().prefix(2)))
    }
}

@main struct FewyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PocketNotes", provider: NotesProvider()) { entry in
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("FEWY").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Link(destination: URL(string: "pocketpress://capture")!) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }.accessibilityLabel("Add a note")
                }
                if entry.notes.isEmpty {
                    Text("Write it before it’s gone.").foregroundStyle(.secondary)
                }
                ForEach(entry.notes) { note in
                    Text(note.text).lineLimit(2).privacySensitive()
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "pocketpress://capture"))
        }
        .configurationDisplayName("Fewy Notes")
        .description("See recent notes and jump straight into writing.")
        .supportedFamilies([.systemMedium])
    }
}
