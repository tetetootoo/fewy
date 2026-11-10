import SwiftUI
import WidgetKit

@main struct FewyApp: App {
    var body: some Scene {
        WindowGroup { NotesScreen().tint(.primary) }
    }
}

struct NotesScreen: View {
    @State private var notes = Notes.load()
    @State private var selectedDay = Date()
    @State private var draft = ""
    @State private var editing: Note?
    @State private var edition = false
    @State private var styles = false
    @State private var failed = false
    @FocusState private var focused: Bool
    private let calendar = Calendar.current
    private var daily: [Note] { notes.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) } }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Image("Wordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Fewy")
                Spacer()
                Button { styles = true } label: {
                    Label("Styles", systemImage: "swatchpalette")
                }
            }
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous day")
                Spacer()
                DatePicker("Day", selection: $selectedDay, displayedComponents: .date).labelsHidden()
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next day")
            }.buttonStyle(.bordered)
            VStack(alignment: .leading, spacing: 16) {
                Text(selectedDay.formatted(.dateTime.day().weekday(.wide)))
                    .font(.largeTitle.bold())
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if daily.isEmpty {
                            Text("Catch a thought before it goes.").foregroundStyle(.secondary)
                        }
                        ForEach(daily) { note in
                            Text(note.text).frame(maxWidth: .infinity, alignment: .leading)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") {
                                        editing = note
                                        draft = note.text
                                        focused = true
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        persist(notes.filter { $0.id != note.id })
                                    }
                                }
                            Divider()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    TextField(editing == nil ? "Add a note" : "Edit note", text: $draft)
                        .focused($focused).submitLabel(.done).onSubmit(save)
                        .padding(13).background(.secondary.opacity(0.10), in: Capsule())
                    Button(action: save) {
                        Image(systemName: editing == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                            .font(.largeTitle)
                    }.accessibilityLabel("Save note")
                    if editing != nil {
                        Button("Cancel") { editing = nil; draft = ""; focused = false }
                    }
                }
                Button {
                    focused = false
                    edition = true
                } label: {
                    Label("Make an edition", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }.disabled(daily.isEmpty)
            }
            .padding(22)
            .background(.background, in: RoundedRectangle(cornerRadius: 34))
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
        .sheet(isPresented: $edition) { EditionEditor(notes: daily, date: selectedDay) }
        .sheet(isPresented: $styles) { StylesGallery() }
        .onChange(of: selectedDay) { _, _ in
            if editing != nil { editing = nil; draft = "" }
        }
        .onOpenURL { url in
            guard url.scheme == "pocketpress", url.host == "capture" else { return }
            edition = false
            styles = false
            if editing != nil { editing = nil; draft = "" }
            selectedDay = .now
            focused = true
        }
        .alert("Couldn’t save notes", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    private func step(_ amount: Int) {
        if let day = calendar.date(byAdding: .day, value: amount, to: selectedDay) { selectedDay = day }
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var updated = notes
        if let editing, let index = updated.firstIndex(where: { $0.id == editing.id }) {
            updated[index].text = text
        } else {
            let date = calendar.isDateInToday(selectedDay) ? Date.now : selectedDay
            updated.insert(Note(text: text, date: date), at: 0)
        }
        if persist(updated) { draft = ""; editing = nil }
    }

    @discardableResult private func persist(_ updated: [Note]) -> Bool {
        do {
            try Notes.save(updated)
            notes = updated
            WidgetCenter.shared.reloadTimelines(ofKind: "PocketNotes")
            return true
        } catch {
            failed = true
            return false
        }
    }
}

struct StylesGallery: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Editions") {
                    Label("Lemon Paper", systemImage: "circle.fill").foregroundStyle(.primary)
                    Label("Studio included", systemImage: "sparkles")
                }
                FewyAdSection(adsEnabled: true)
            }
            .task {
                FewyAds.shared.setAdsEnabled(true)
                await FewyAds.shared.prepare()
            }
            .navigationTitle("Styles")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
