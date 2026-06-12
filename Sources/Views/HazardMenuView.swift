import SwiftUI

// MARK: - Hazard Menu View (Radial Menu)

struct HazardMenuView: View {
    let onSelect: (HazardType) -> Void
    @Environment(\.dismiss) private var dismiss

    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Marcar Perigo")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(HazardType.allCases, id: \.self) { type in
                        Button {
                            onSelect(type)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: type.iconName)
                                    .font(.system(size: 28))

                                Text(type.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(width: 90, height: 90)
                            .background(Color(.systemGray5))
                            .cornerRadius(16)
                        }
                        .accessibilityLabel(type.displayName)
                        .accessibilityHint("Marca um alerta de \(type.displayName) no mapa")
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal)

                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Cancelar")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)
            }
        }
        .presentationDetents([.medium])
    }
}
