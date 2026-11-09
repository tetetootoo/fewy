import Foundation

struct Note: Codable, Identifiable {
    var id = UUID()
    var text: String
    var date = Date()
}

enum Notes {
    static let group = "group.com.bramlen.pocketpress"
    private static let key = "notes.v1"
    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func load() -> [Note] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Note].self, from: data)) ?? []
    }

    static func save(_ notes: [Note]) throws {
        defaults.set(try JSONEncoder().encode(notes), forKey: key)
    }
}
