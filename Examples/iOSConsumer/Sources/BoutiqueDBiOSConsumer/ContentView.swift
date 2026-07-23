import BoutiqueDB
import SwiftUI

@MainActor
struct ContentView: View {
  @State private var db: BoutiqueDB?
  @State private var errorText: String?

  var body: some View {
    NavigationStack {
      Group {
        if let db {
          NoteListView(db: db)
        } else if let errorText {
          ContentUnavailableView("Open failed", systemImage: "xmark.octagon", description: Text(errorText))
        } else {
          ProgressView("Opening…")
        }
      }
      .navigationTitle("Notes")
      .task {
        await openDatabase()
      }
    }
  }

  private func openDatabase() async {
    do {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ios-consumer-\(UUID().uuidString).db")
      let config = BoutiqueDBConfiguration(
        url: url,
        startListening: true,
        schemaModels: [Note.self]
      )
      db = try await BoutiqueDB.open(config)
    } catch {
      errorText = error.localizedDescription
    }
  }
}

@MainActor
struct NoteListView: View {
  let db: BoutiqueDB
  @State private var searchText = ""
  @State private var draftTitle = ""
  @State private var liveQuery: LiveQuery<Note>

  init(db: BoutiqueDB) {
    self.db = db
    _liveQuery = State(wrappedValue: LiveQuery(db) { Note.all.asSelect() })
  }

  private func makeQuery(for text: String) -> @Sendable () -> SelectOf<Note> {
    if text.isEmpty {
      return { Note.all.asSelect() }
    }
    return {
      Note.all.where {
        $0.title.match(text) || $0.body.match(text)
      }.asSelect()
    }
  }

  var body: some View {
    List {
      ForEach(liveQuery.wrappedValue, id: \.id) { note in
        VStack(alignment: .leading) {
          Text(note.title).font(.headline)
          Text(note.body).font(.subheadline).foregroundStyle(.secondary)
        }
      }

      HStack {
        TextField("New note title", text: $draftTitle)
        Button("Add") {
          Task { await addNote() }
        }
        .disabled(draftTitle.isEmpty)
      }
    }
    .searchable(text: $searchText, prompt: "Search notes")
    .onChange(of: searchText) { _, newValue in
      liveQuery.setQuery(makeQuery(for: newValue))
    }
  }

  private func addNote() async {
    let title = draftTitle
    draftTitle = ""
    do {
      _ = try await db.write { conn in
        try await Note.insert {
          Note(id: UUID().uuidString, title: title, body: "Created on iOS")
        }.execute(conn.connection)
      }
    } catch {
      // In a real app, surface this error.
    }
  }
}
