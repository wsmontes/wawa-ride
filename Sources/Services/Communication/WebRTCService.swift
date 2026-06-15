import Foundation
@preconcurrency import WebRTC
import os.log

/// WebRTC peer connections — all operations on main thread.
final class WebRTCService: NSObject, ObservableObject, @unchecked Sendable {

    @Published var peers: [String: PeerState] = [:]
    enum PeerState: String { case connecting, connected, failed }

    private let factory: RTCPeerConnectionFactory
    private let iceServers: [RTCIceServer]
    private let localRiderID: String
    private let log = Logger(subsystem: "com.wawaride", category: "WebRTC")

    private var connections: [String: RTCPeerConnection] = [:]
    private var dataChannels: [String: RTCDataChannel] = [:]

    var onDataReceived: ((Data, String) -> Void)?
    var onOutgoingSignaling: ((Data, String) -> Void)?

    init(localRiderID: String) {
        self.localRiderID = localRiderID
        assert(Thread.isMainThread, "WebRTCService must be initialized on main thread")
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory()
        var servers: [RTCIceServer] = []
        for url in TURNConfig.stunURLs {
            servers.append(RTCIceServer(urlStrings: [url]))
        }
        servers.append(RTCIceServer(
            urlStrings: TURNConfig.turnURLs,
            username: TURNConfig.turnUsername,
            credential: TURNConfig.turnCredential
        ))
        self.iceServers = servers
        super.init()
        self.log.info("WebRTC ready — \(self.iceServers.count) ICE servers on main thread")
        AppLogger.shared.info("WebRTC init OK — TURN: \(TURNConfig.turnUsername.isEmpty ? "NO" : "YES")")
    }

    func createOffer(for riderID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard connections[riderID] == nil else { return }
        peers[riderID] = .connecting

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.continualGatheringPolicy = .gatherContinually
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            peers[riderID] = .failed
            AppLogger.shared.error("WebRTC: failed to create peerConnection for \(riderID)")
            return
        }
        pc.delegate = self
        connections[riderID] = pc

        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = false
        if let dc = pc.dataChannel(forLabel: "wawa-location", configuration: dcConfig) {
            dc.delegate = self
            dataChannels[riderID] = dc
        }

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "false", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )
        pc.offer(for: offerConstraints) { [weak self] sdp, error in
            guard let self else { return }
            guard let sdp else {
                self.peers[riderID] = .failed
                AppLogger.shared.error("WebRTC: offer failed for \(riderID): \(error?.localizedDescription ?? "")")
                return
            }
            pc.setLocalDescription(sdp) { err in
                if let err { self.log.error("setLocal: \(err.localizedDescription)") }
            }
            if let payload = sdp.sdp.data(using: .utf8) {
                AppLogger.shared.info("WebRTC: offer ready for \(riderID) (\(payload.count)b)")
                self.onOutgoingSignaling?(payload, riderID)
            }
        }
    }

    func onSignalingReceived(_ data: Data, from riderID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let text = String(data: data, encoding: .utf8) else { return }
        AppLogger.shared.info("WebRTC: signaling recv \(data.count)b from \(riderID)")
        // Detect SDP type by content (SDP starts with v=)
        if text.hasPrefix("v=") {
            // It's an SDP — check if offer or answer
            if text.contains("a=setup:actpass") || text.lowercased().contains("type offer") {
                handleOffer(text, from: riderID)
            } else {
                handleAnswer(text, from: riderID)
            }
        }
    }

    func send(_ data: Data, to riderID: String) {
        guard let dc = dataChannels[riderID], dc.readyState == .open else { return }
        dc.sendData(RTCDataBuffer(data: data, isBinary: true))
    }

    func broadcast(_ data: Data) {
        for (_, dc) in dataChannels where dc.readyState == .open {
            dc.sendData(RTCDataBuffer(data: data, isBinary: true))
        }
    }

    func disconnect(peer riderID: String) {
        dataChannels[riderID]?.close()
        dataChannels.removeValue(forKey: riderID)
        connections[riderID]?.close()
        connections.removeValue(forKey: riderID)
        peers.removeValue(forKey: riderID)
    }
}

// MARK: - SDP Handlers

private extension WebRTCService {
    func handleOffer(_ sdp: String, from riderID: String) {
        peers[riderID] = .connecting
        AppLogger.shared.info("WebRTC: handling OFFER from \(riderID)")

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.continualGatheringPolicy = .gatherContinually

        let emptyConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: emptyConstraints, delegate: nil) else {
            peers[riderID] = .failed
            return
        }
        pc.delegate = self
        connections[riderID] = pc

        pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { [weak self] err in
            guard let self else { return }
            if let err { self.log.error("setRemote: \(err.localizedDescription)") }
            pc.answer(for: emptyConstraints) { answerSDP, _ in
                guard let answerSDP else { self.peers[riderID] = .failed; return }
                pc.setLocalDescription(answerSDP) { _ in }
                if let payload = answerSDP.sdp.data(using: .utf8) {
                    AppLogger.shared.info("WebRTC: answer ready for \(riderID) (\(payload.count)b)")
                    self.onOutgoingSignaling?(payload, riderID)
                }
            }
        }
    }

    func handleAnswer(_ sdp: String, from riderID: String) {
        AppLogger.shared.info("WebRTC: handling ANSWER from \(riderID)")
        connections[riderID]?.setRemoteDescription(
            RTCSessionDescription(type: .answer, sdp: sdp)
        ) { [weak self] err in
            if let self, let err { self.log.error("setRemote answer: \(err.localizedDescription)") }
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ pc: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        guard let entry = connections.first(where: { $0.value == pc }) else { return }
        AppLogger.shared.info("WebRTC: \(entry.key) → \(state.rawValue)")
        switch state {
        case .connected: peers[entry.key] = .connected
        case .failed, .disconnected: peers[entry.key] = .failed
        case .connecting: peers[entry.key] = .connecting
        default: break
        }
    }

    func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let entry = connections.first(where: { $0.value == pc }) else { return }
        let dict: [String: String] = [
            "sdp": candidate.sdp, "sdpMLineIndex": "\(candidate.sdpMLineIndex)", "sdpMid": candidate.sdpMid ?? ""
        ]
        if let json = try? JSONSerialization.data(withJSONObject: dict),
           let jsonStr = String(data: json, encoding: .utf8) {
            self.onOutgoingSignaling?(jsonStr.data(using: .utf8)!, entry.key)
        }
    }

    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard let entry = connections.first(where: { $0.value == pc }) else { return }
        AppLogger.shared.info("WebRTC ICE: \(entry.key) → \(newState.rawValue)")
    }

    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard let entry = connections.first(where: { $0.value == pc }) else { return }
        AppLogger.shared.info("WebRTC ICE gathering: \(entry.key) → \(newState.rawValue)")
    }

    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        guard let entry = connections.first(where: { $0.value == pc }) else { return }
        AppLogger.shared.info("WebRTC: DataChannel opened from \(entry.key)")
        dataChannel.delegate = self
        dataChannels[entry.key] = dataChannel
    }
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCSignalingState) {}
}

// MARK: - RTCDataChannelDelegate

extension WebRTCService: RTCDataChannelDelegate {
    func dataChannel(_ dc: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let entry = dataChannels.first(where: { $0.value == dc }) {
            onDataReceived?(buffer.data, entry.key)
        }
    }
    func dataChannelDidChangeState(_ dc: RTCDataChannel) {
        log.debug("DC state: \(dc.readyState.rawValue)")
    }
}
