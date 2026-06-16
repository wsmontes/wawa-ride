import SwiftUI

struct CreateRideView: View {
    @ObservedObject var state: RideState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🏍️")
                .font(.system(size: 64))
            Text("Wawa Ride")
                .font(.largeTitle).bold()

            VStack(spacing: 12) {
                TextField("Nome do passeio", text: $state.rideName)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.secondary)
                    Text("Victoria, BC")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 32)

            Button(action: { state.createRide() }) {
                Text("Criar Passeio")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Text("BLE mesh será ativado automaticamente")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}
