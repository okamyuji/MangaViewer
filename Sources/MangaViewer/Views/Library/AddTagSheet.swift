import SwiftUI

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
        #if os(macOS)
            let srgb = NSColor(self).usingColorSpace(.sRGB)?.cgColor
        #else
            let srgb = CGColorSpace(name: CGColorSpace.sRGB).flatMap {
                UIColor(self).cgColor.converted(to: $0, intent: .defaultIntent, options: nil)
            }
        #endif
        guard let components = srgb?.components, components.count >= 3 else { return nil }
        let red = Int((components[0] * 255).rounded())
        let green = Int((components[1] * 255).rounded())
        let blue = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
