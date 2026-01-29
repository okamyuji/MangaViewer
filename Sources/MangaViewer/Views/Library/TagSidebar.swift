import SwiftData
import SwiftUI

struct TagSidebar: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Tag.name) private var tags: [Tag]
  @State private var selectedSection: SidebarSection? = .all
  @State private var showAddTagSheet = false
  @State private var newTagName = ""

  enum SidebarSection: Hashable {
    case all
    case recent
    case tag(Tag)
  }

  var body: some View {
    List(selection: $selectedSection) {
      Section("Library") {
        Label("All Books", systemImage: "books.vertical")
          .tag(SidebarSection.all)

        Label("Recently Opened", systemImage: "clock")
          .tag(SidebarSection.recent)
      }

      Section("Tags") {
        ForEach(tags) { tag in
          Label(tag.name, systemImage: "tag")
            .foregroundStyle(Color(hex: tag.colorHex) ?? .accentColor)
            .tag(SidebarSection.tag(tag))
            .contextMenu {
              Button("Delete", role: .destructive) {
                deleteTag(tag)
              }
            }
        }

        Button {
          showAddTagSheet = true
        } label: {
          Label("Add Tag", systemImage: "plus")
        }
        .buttonStyle(.plain)
      }
    }
    .listStyle(.sidebar)
    .sheet(isPresented: $showAddTagSheet) {
      AddTagSheet(isPresented: $showAddTagSheet) { name, colorHex in
        addTag(name: name, colorHex: colorHex)
      }
    }
  }

  private func addTag(name: String, colorHex: String) {
    let tag = Tag(name: name, colorHex: colorHex)
    modelContext.insert(tag)
    try? modelContext.save()
  }

  private func deleteTag(_ tag: Tag) {
    modelContext.delete(tag)
    try? modelContext.save()
  }
}

struct AddTagSheet: View {
  @Binding var isPresented: Bool
  @State private var tagName = ""
  @State private var selectedColor = Color.blue

  let onAdd: (String, String) -> Void

  var body: some View {
    VStack(spacing: 20) {
      Text("Add New Tag")
        .font(.headline)

      TextField("Tag Name", text: $tagName)
        .textFieldStyle(.roundedBorder)

      ColorPicker("Tag Color", selection: $selectedColor)

      HStack {
        Button("Cancel") {
          isPresented = false
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Add") {
          onAdd(tagName, selectedColor.toHex() ?? "#007AFF")
          isPresented = false
        }
        .keyboardShortcut(.defaultAction)
        .disabled(tagName.isEmpty)
      }
    }
    .padding()
    .frame(width: 300)
  }
}

extension Color {
  init?(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    guard hexSanitized.count == 6,
      let hexNumber = UInt64(hexSanitized, radix: 16)
    else {
      return nil
    }

    let red = Double((hexNumber & 0xFF0000) >> 16) / 255.0
    let green = Double((hexNumber & 0x00FF00) >> 8) / 255.0
    let blue = Double(hexNumber & 0x0000FF) / 255.0

    self.init(red: red, green: green, blue: blue)
  }

  func toHex() -> String? {
    guard let components = NSColor(self).cgColor.components else { return nil }
    let red = Int(components[0] * 255)
    let green = Int(components[1] * 255)
    let blue = Int(components[2] * 255)
    return String(format: "#%02X%02X%02X", red, green, blue)
  }
}

#Preview {
  TagSidebar()
    .modelContainer(for: Tag.self, inMemory: true)
}
