import SwiftUI

// MARK: - Room List View

struct RoomListView: View {
    @StateObject private var roomService = RoomService.shared
    @State private var showCreateRoom = false
    @State private var selectedRoom: Room?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(roomService.rooms.filter { $0.isActive }) { room in
                    Button {
                        selectedRoom = room
                        AppState.shared.currentRoomId = room.id
                        dismiss()
                    } label: {
                        RoomRow(room: room, unreadCount: unreadCount(for: room.id))
                    }
                }

                Section {
                    Button {
                        showCreateRoom = true
                    } label: {
                        Label("Nova Sala", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Salas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Voltar ao mapa") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCreateRoom) {
                CreateRoomView()
            }
            .sheet(item: $selectedRoom) { room in
                RoomDetailView(room: room)
            }
        }
    }

    func unreadCount(for roomId: String) -> Int {
        let messages = roomService.messagesByRoom[roomId] ?? []
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        return messages.filter { !$0.playedBy.contains(myId) }.count
    }
}

// MARK: - Room Row

struct RoomRow: View {
    let room: Room
    let unreadCount: Int

    var body: some View {
        HStack {
            Image(systemName: roomIcon)
                .font(.title2)
                .foregroundColor(roomColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(room.name)
                        .font(.headline)

                    if room.isPrivate {
                        Image(systemName: "lock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("\(room.members.count) membros • \(room.type.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    var roomIcon: String {
        switch room.type {
        case .general: "house"
        case .voice: "waveform"
        case .messaging: "message"
        case .alerts: "bell"
        case .direct: "person"
        }
    }

    var roomColor: Color {
        switch room.type {
        case .general: .orange
        case .voice: .green
        case .messaging: .blue
        case .alerts: .red
        case .direct: .purple
        }
    }
}

// MARK: - Create Room View

struct CreateRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var roomType: RoomType = .voice
    @State private var isPrivate = false
    @State private var selectedMembers: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome da sala", text: $roomName)
                }

                Section("Tipo") {
                    Picker("Tipo", selection: $roomType) {
                        Text("🎙️ Voz ao vivo").tag(RoomType.voice)
                        Text("💬 Mensagens").tag(RoomType.messaging)
                    }
                }

                Section("Privacidade") {
                    Toggle("🔒 Sala privada", isOn: $isPrivate)
                }

                Section("Membros") {
                    ForEach(AppState.shared.participants, id: \.riderId) { rider in
                        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
                        if rider.riderId != myId {
                            HStack {
                                Text(rider.name)
                                Spacer()
                                if selectedMembers.contains(rider.riderId) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.orange)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedMembers.contains(rider.riderId) {
                                    selectedMembers.remove(rider.riderId)
                                } else {
                                    selectedMembers.insert(rider.riderId)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nova Sala")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Criar") {
                        _ = RoomService.shared.createRoom(
                            name: roomName,
                            type: roomType,
                            isPrivate: isPrivate,
                            memberIds: Array(selectedMembers)
                        )
                        dismiss()
                    }
                    .disabled(roomName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Room Detail View

struct RoomDetailView: View {
    let room: Room
    @StateObject private var viewModel = RoomDetailViewModel()
    @State private var isRecording = false

    var body: some View {
        VStack {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(room.name)
                        .font(.headline)
                    Text("\(room.members.count) membros")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()

            // Messages timeline
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        VoiceMessageBubble(message: message) {
                            VoiceService.shared.playMessage(message)
                        }
                    }
                }
                .padding()
            }

            // Action bar
            HStack(spacing: 20) {
                // Record async message
                Button {
                    if isRecording {
                        _ = VoiceService.shared.stopRecording()
                        isRecording = false
                    } else {
                        VoiceService.shared.startRecording(roomId: room.id)
                        isRecording = true
                    }
                } label: {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle")
                        .font(.system(size: 36))
                        .foregroundColor(isRecording ? .red : .orange)
                }

                // PTT for live voice
                if room.type == .voice || room.type == .general || room.type == .direct {
                    Button {
                        // PTT handled via long press
                    } label: {
                        Text("🎤 FALAR")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .cornerRadius(24)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            viewModel.loadMessages(roomId: room.id)
        }
    }
}

@MainActor
final class RoomDetailViewModel: ObservableObject {
    @Published var messages: [VoiceMessage] = []

    func loadMessages(roomId: String) {
        messages = LocalStore.shared.loadVoiceMessages(for: roomId)
    }
}

// MARK: - Voice Message Bubble

struct VoiceMessageBubble: View {
    let message: VoiceMessage
    let onPlay: () -> Void
    @State private var isPlaying = false

    var isMine: Bool {
        message.fromRiderId == UserDefaults.standard.string(forKey: "riderProfileId")
    }

    var body: some View {
        HStack {
            if isMine { Spacer() }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine {
                    Text(message.fromRiderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    isPlaying = true
                    onPlay()
                    DispatchQueue.main.asyncAfter(deadline: .now() + message.duration) {
                        isPlaying = false
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                            .font(.title2)

                        Text(formatDuration(message.duration))
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.orange : Color(.systemGray5))
                    .foregroundColor(isMine ? .white : .primary)
                    .cornerRadius(16)
                }

                HStack(spacing: 4) {
                    Text(message.sentAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if isMine {
                        Image(systemName: message.isDeliveredToMe ? "checkmark" : "clock")
                            .font(.caption2)
                            .foregroundColor(message.isPlayedByMe ? .blue : .secondary)
                    }
                }
            }

            if !isMine { Spacer() }
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
        return "0:\(String(format: "%02d", seconds))"
    }
}
