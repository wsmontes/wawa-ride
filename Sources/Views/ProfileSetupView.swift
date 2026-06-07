import SwiftUI

// MARK: - Profile Setup View

struct ProfileSetupView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "motorcycle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("WAWA Ride")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Configure seu perfil de piloto")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)

                // Avatar
                Button {
                    viewModel.showPhotoPicker = true
                } label: {
                    if let photoData = viewModel.photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.orange, lineWidth: 3))
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 100, height: 100)

                            Text(viewModel.initials)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        .overlay(Circle().stroke(Color.orange, lineWidth: 3))
                    }
                }
                .padding(.bottom, 8)

                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nome ou apelido")
                        .font(.headline)

                    TextField("Seu nome", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal)

                // Bike model
                VStack(alignment: .leading, spacing: 8) {
                    Text("Moto (opcional)")
                        .font(.headline)

                    TextField("Ex: BMW R1250GS", text: $viewModel.bikeModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal)

                // Role selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Função padrão")
                        .font(.headline)
                        .padding(.horizontal)

                    Picker("Função", selection: $viewModel.defaultRole) {
                        ForEach(RideRole.allCases, id: \.self) { role in
                            Label(role.displayName, systemImage: roleIcon(for: role))
                                .tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                Spacer()

                // Save button
                Button {
                    viewModel.save()
                    dismiss()
                } label: {
                    Text("SALVAR E CONTINUAR")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.canSave ? Color.orange : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!viewModel.canSave)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .sheet(isPresented: $viewModel.showPhotoPicker) {
                // Photo picker placeholder
                Text("Selecionar foto")
            }
        }
    }

    func roleIcon(for role: RideRole) -> String {
        switch role {
        case .leader: "star"
        case .rider: "person"
        case .sweeper: "shield"
        }
    }
}

// MARK: - Profile ViewModel

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var bikeModel = ""
    @Published var defaultRole: RideRole = .rider
    @Published var photoData: Data?
    @Published var showPhotoPicker = false

    var initials: String {
        name.components(separatedBy: " ")
            .prefix(2).compactMap { $0.first }.map { String($0) }.joined().uppercased()
    }

    var canSave: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2
    }

    init() {
        if let existing = LocalStore.shared.loadProfile() {
            name = existing.name
            bikeModel = existing.bikeModel ?? ""
            defaultRole = existing.defaultRole
            photoData = existing.photoData
        }
    }

    func save() {
        let profile = RiderProfile(
            id: LocalStore.shared.loadProfile()?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            bikeModel: bikeModel.isEmpty ? nil : bikeModel.trimmingCharacters(in: .whitespaces),
            photoData: photoData,
            defaultRole: defaultRole
        )
        LocalStore.shared.saveProfile(profile)
    }
}
