import SwiftUI
import UIKit

struct Sticker: Identifiable {
    var id = UUID()
    let symbol: String
    var position = CGPoint(x: 0.75, y: 0.22)
    var size: CGFloat = 1
    var angle: Double = 0
}

enum Paper: String, CaseIterable, Identifiable {
    case lemon = "Lemon", lilac = "Lilac", mint = "Mint"
    var id: Self { self }
    var color: Color {
        switch self {
        case .lemon: Color(red: 248/255, green: 248/255, blue: 226/255)
        case .lilac: Color(red: 0.94, green: 0.90, blue: 0.98)
        case .mint: Color(red: 0.89, green: 0.95, blue: 0.91)
        }
    }
}

struct StoryCanvas: View {
    let title: String
    let notes: [Note]
    let date: Date
    let paper: Paper
    let credit: Bool
    let stickers: [Sticker]

    var body: some View {
        ZStack(alignment: .topLeading) {
            paper.color
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 13) {
                    Text(date.formatted(.dateTime.day().month(.abbreviated)).uppercased())
                        .font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(.gray)
                    Text(title.isEmpty ? "Little things" : title)
                        .font(.system(size: 27, weight: .bold)).lineLimit(3)
                    Rectangle().fill(.gray.opacity(0.35)).frame(height: 1)
                    ForEach(notes) { note in
                        Text(note.text).font(.system(size: 15)).lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.black)
                .padding(22)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 46)
            .frame(width: 360, height: 640)
            ForEach(stickers) { sticker in
                Text(sticker.symbol).font(.system(size: 40 * sticker.size))
                    .rotationEffect(.degrees(sticker.angle))
                    .position(x: sticker.position.x * 360, y: sticker.position.y * 640)
            }
            if credit {
                Text("Made with Fewy")
                    .font(.system(size: 10, design: .monospaced)).tracking(1)
                    .foregroundStyle(Color.black.opacity(0.65))
                    .position(x: 180, y: 594)
            }
        }.frame(width: 360, height: 640).clipped()
    }
}

struct EditionEditor: View {
    @EnvironmentObject private var studio: Studio
    @Environment(\.dismiss) private var dismiss
    let notes: [Note]
    let date: Date
    @State private var title = ""
    @State private var included: Set<UUID> = []
    @State private var stickers: [Sticker] = []
    @State private var selected: UUID?
    @State private var paper = Paper.lemon
    @State private var credit = true
    @State private var paywall = false
    @State private var picker = false
    @State private var selection = false
    @State private var export: URL?
    @State private var failed = false
    private var selectedIndex: Int? { stickers.firstIndex { $0.id == selected } }
    private var chosen: [Note] { notes.filter { included.contains($0.id) } }
    private var canvas: StoryCanvas {
        StoryCanvas(title: title, notes: chosen, date: date, paper: studio.unlocked ? paper : .lemon,
                    credit: !studio.unlocked || credit, stickers: stickers)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField("Edition title", text: $title).textFieldStyle(.roundedBorder)
                    GeometryReader { geometry in
                        let scale = geometry.size.width / 360
                        ZStack {
                            StoryCanvas(title: title, notes: chosen, date: date, paper: studio.unlocked ? paper : .lemon,
                                        credit: !studio.unlocked || credit, stickers: [])
                                .scaleEffect(scale)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            ForEach($stickers) { $sticker in
                                Text(sticker.symbol).font(.system(size: 40 * sticker.size * scale))
                                    .rotationEffect(.degrees(sticker.angle))
                                    .padding(4)
                                    .overlay {
                                        if selected == sticker.id {
                                            RoundedRectangle(cornerRadius: 6).stroke(.gray, style: StrokeStyle(dash: [3]))
                                        }
                                    }
                                    .position(x: sticker.position.x * geometry.size.width,
                                              y: sticker.position.y * geometry.size.height)
                                    .onTapGesture { selected = sticker.id }
                                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("story")).onChanged { value in
                                        selected = sticker.id
                                        sticker.position = CGPoint(
                                            x: min(0.96, max(0.04, value.location.x / geometry.size.width)),
                                            y: min(0.96, max(0.04, value.location.y / geometry.size.height))
                                        )
                                    })
                            }
                        }.coordinateSpace(name: "story").clipped()
                    }.aspectRatio(9.0 / 16, contentMode: .fit)
                    HStack {
                        Button("Add sticker", systemImage: "face.smiling") { picker = true }
                        Button("Choose notes", systemImage: "list.bullet") { selection = true }
                    }.buttonStyle(.bordered)
                    if let index = selectedIndex {
                        VStack {
                            Slider(value: $stickers[index].size, in: 0.5...2) { Text("Sticker size") }
                            Slider(value: $stickers[index].angle, in: -180...180) { Text("Sticker rotation") }
                            Button("Remove sticker", role: .destructive) {
                                stickers.remove(at: index)
                                selected = nil
                            }
                        }
                    }
                    Menu("Background · \(paper.rawValue)") {
                        ForEach(Paper.allCases) { option in
                            Button(option.rawValue) {
                                if studio.unlocked || option == .lemon { paper = option }
                                else { paywall = true }
                            }
                        }
                    }
                    if studio.unlocked { Toggle("Show Fewy credit", isOn: $credit) }
                    Button("Prepare Story", systemImage: "square.and.arrow.up", action: render)
                        .buttonStyle(.borderedProminent).disabled(chosen.isEmpty)
                    if let export {
                        ShareLink(item: export).buttonStyle(.bordered)
                    }
                }.frame(maxWidth: 360).padding(16)
            }
            .navigationTitle("Your edition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .onAppear { if included.isEmpty { included = Set(notes.prefix(3).map(\.id)) } }
            .onChange(of: title) { _, _ in clearExport() }
            .onChange(of: included) { _, _ in clearExport() }
            .onChange(of: paper) { _, _ in clearExport() }
            .onChange(of: credit) { _, _ in clearExport() }
            .onChange(of: studio.unlocked) { _, _ in clearExport() }
            .onChange(of: stickers.map { "\($0.id):\($0.position):\($0.size):\($0.angle)" }) { _, _ in clearExport() }
            .sheet(isPresented: $paywall) { StudioPaywall(studio: studio) }
            .sheet(isPresented: $selection) {
                NavigationStack {
                    List(notes) { note in
                        Button {
                            if included.contains(note.id) { included.remove(note.id) }
                            else if included.count < 3 { included.insert(note.id) }
                        } label: {
                            HStack {
                                Text(note.text)
                                Spacer()
                                if included.contains(note.id) { Image(systemName: "checkmark") }
                            }
                        }.disabled(included.count == 3 && !included.contains(note.id))
                    }
                    .navigationTitle("Pick up to three notes")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { selection = false } }
                }
            }
            .sheet(isPresented: $picker) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add a sticker").font(.title2.bold())
                    HStack {
                        ForEach(["🪩", "🐈", "⭐", "🌷", "🐢"], id: \.self) { symbol in
                            Button { add(symbol) } label: { Text(symbol).font(.largeTitle) }
                        }
                    }
                    if studio.unlocked {
                        HStack {
                            ForEach(["🪲", "🪼", "🦢", "🎱", "🪭"], id: \.self) { symbol in
                                Button { add(symbol) } label: { Text(symbol).font(.largeTitle) }
                            }
                        }
                    } else {
                        Button("Explore Studio stickers") {
                            picker = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(400))
                                paywall = true
                            }
                        }
                    }
                }.padding(24).presentationDetents([.medium])
            }
            .alert("Couldn’t create the Story", isPresented: $failed) { Button("OK", role: .cancel) {} }
        }
    }

    private func add(_ symbol: String) {
        let sticker = Sticker(symbol: symbol)
        stickers.append(sticker)
        selected = sticker.id
        picker = false
    }

    private func clearExport() {
        guard let export else { return }
        try? FileManager.default.removeItem(at: export)
        self.export = nil
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: canvas.environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { failed = true; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Fewy-\(UUID()).png")
        do {
            try data.write(to: url, options: .atomic)
            clearExport()
            export = url
        } catch { failed = true }
    }
}
