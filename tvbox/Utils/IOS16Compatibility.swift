import SwiftUI

extension View {
    /// Capture the previous render's value; unlike replacing old with new this
    /// preserves HomeView's category-change comparison semantics.
    func onCompatibleChange<Value: Equatable>(of value: Value,
        perform action: @escaping (Value, Value) -> Void) -> some View {
        onChange(of: value) { [value] newValue in action(value, newValue) }
    }
}

struct CompatibleUnavailableView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: Text?

    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle).foregroundColor(.secondary)
            Text(title).font(.headline)
            if let description { description.foregroundColor(.secondary).multilineTextAlignment(.center) }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
