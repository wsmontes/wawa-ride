import Foundation
@preconcurrency import WebRTC
import os.log

/// Manages WebRTC peer connections for internet-routable P2P communication.
/// Signaling is exchanged via MultipeerConnectivity (zero server).
final class WebRTCService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published

    @Published var peers: [String: PeerState] = [:]

    enum PeerState: String { case connecting, connected, failed }

    // MARK: - Properties

    private let factory: RTCPeerConnectionFactory
    private let iceServers: [RTCIceServer]
    private let localRiderID: String
    private let log = Logger(subsystem: "com.wawaride", category: "WebRTC")

    /// One RTCPeerConnection per remote peer.
    private var connections: [String: RTCPeerConnection] = [:]
    private var dataChannels: [String: RTCDataChannel] = [:]

    /// Called when a DataChannel message is received.
    var onDataReceived: ((Data, String) -> Void)?

    /// Called when SDP/ICE needs to be sent to a peer via the signaling channel.
    var onOutgoingSignaling: ((Data, String) -> Void)?

    // MARK: - Init

    init(localRiderID: String) {
        self.localRiderID = localRiderID
        factory = RTCPeerConnectionFactory()

        var servers: [RTCIceServer] = []

        // STUN servers (always included)
        for url in TURNConfig.stunURLs {
            servers.append(RTCIceServer(urlStrings: [url]))
        }

        // TURN server (fallback)
        servers.append(RTCIceServer(
            urlStrings: TURNConfig.turnURLs,
            username: TURNConfig.turnUsername,
            credential: TURNConfig.turnCredential
        ))

        iceServers = servers
        log.info("WebRTC configured with \(servers.count) ICE servers")
        super.init()
    }

    // MARK: - Public API

    /// Create a peer connection for a new rider and initiate the offer.
    func createOffer(for riderID: String) {
        peers[riderID] = .connecting

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.continualGatheringPolicy = .gatherContinually
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        guard let pc = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: nil
        ) else {
            log.error("Failed to create peer connection for \(riderID)")
            peers[riderID] = .failed
            return
        }

        pc.delegate = self
        connections[riderID] = pc

        // Create DataChannel
        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = false
        dcConfig.isNegotiated = false

        if let dc = pc.dataChannel(forLabel: "wawa-location", configuration: dcConfig) {
            dc.delegate = self
            dataChannels[riderID] = dc
        }

        // Create offer
        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "false", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )

        pc.offer(for: offerConstraints) { [weak self] sdp, error in
            guard let self else { return }
            guard let sdp else {
                self.log.error("Offer failed: \(error?.localizedDescription ?? "unknown")")
                self.peers[riderID] = .failed
                return
            }
            let handler: (Error?) -> Void = { err in
                if let err { self.log.error("setLocalDescription: \(err.localizedDescription)") }
            }
            pc.setLocalDescription(sdp, completionHandler: handler)
            // Send SDP via signaling channel
            if let data = sdp.sdp.data(using: .utf8) {
                var payload = "OFFER:".data(using: .utf8) ?? Data()
                payload.append(data)
                self.onOutgoingSignaling?(payload, riderID)
            }
        }
    }

    /// Handle incoming signaling data from MultipeerConnectivity.
    func onSignalingReceived(_ data: Data, from riderID: String) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        if text.hasPrefix("OFFER:") {
            handleOffer(String(text.dropFirst(7)), from: riderID)
        } else if text.hasPrefix("ANSWER:") {
            handleAnswer(String(text.dropFirst(7)), from: riderID)
        } else if text.hasPrefix("ICE:") {
            handleICECandidate(String(text.dropFirst(4)), from: riderID)
        }
    }

    /// Send data to a specific peer via DataChannel.
    func send(_ data: Data, to riderID: String) {
        guard let dc = dataChannels[riderID] else {
            log.warning("No DataChannel for \(riderID)")
            return
        }
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        dc.sendData(buffer)
    }

    /// Broadcast data to all connected peers.
    func broadcast(_ data: Data) {
        for (_, dc) in dataChannels where dc.readyState == .open {
            let buffer = RTCDataBuffer(data: data, isBinary: true)
            dc.sendData(buffer)
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

// MARK: - SDP / ICE Handlers

private extension WebRTCService {

    func makeBaseConfig() -> RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.continualGatheringPolicy = .gatherContinually
        return config
    }

    func emptyConstraints() -> RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    }

    func handleOffer(_ sdp: String, from riderID: String) {
        peers[riderID] = .connecting

        guard let pc = factory.peerConnection(
            with: makeBaseConfig(),
            constraints: emptyConstraints(),
            delegate: nil
        ) else {
            peers[riderID] = .failed
            return
        }
        pc.delegate = self
        connections[riderID] = pc

        let offerSDP = RTCSessionDescription(type: .offer, sdp: sdp)

        pc.setRemoteDescription(offerSDP) { [weak self] err in
            guard let self else { return }
            if let err { self.log.error("setRemoteDescription: \(err.localizedDescription)") }

            pc.answer(for: emptyConstraints()) { answerSDP, error in
                guard let answerSDP else {
                    self.peers[riderID] = .failed
                    return
                }
                pc.setLocalDescription(answerSDP) { _ in }
                if let data = answerSDP.sdp.data(using: .utf8) {
                    var payload = "ANSWER:".data(using: .utf8) ?? Data()
                    payload.append(data)
                    self.onOutgoingSignaling?(payload, riderID)
                }
            }
        }
    }

    func handleAnswer(_ sdp: String, from riderID: String) {
        let answerSDP = RTCSessionDescription(type: .answer, sdp: sdp)
        connections[riderID]?.setRemoteDescription(answerSDP) { [weak self] err in
            guard let self else { return }
            if let err { self.log.error("setRemoteDescription answer: \(err.localizedDescription)") }
        }
    }

    func handleICECandidate(_ candidateJSON: String, from riderID: String) {
        guard let data = candidateJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let sdp = dict["sdp"],
              let sdpMLineIndexStr = dict["sdpMLineIndex"],
              let sdpMLineIndex = Int32(sdpMLineIndexStr),
              let sdpMid = dict["sdpMid"]
        else { return }

        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        connections[riderID]?.add(candidate) { [weak self] err in
            guard let self else { return }
            if let err { self.log.error("addICECandidate: \(err.localizedDescription)") }
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        if let entry = connections.first(where: { $0.value == peerConnection }) {
            let riderID = entry.key
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch state {
                case .connected:
                    self.peers[riderID] = .connected
                    self.log.info("WebRTC connected: \(riderID)")
                case .failed, .disconnected:
                    self.peers[riderID] = .failed
                    self.log.warning("WebRTC \(state.rawValue): \(riderID)")
                case .connecting:
                    self.peers[riderID] = .connecting
                default: break
                }
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let entry = connections.first(where: { $0.value == peerConnection }) else { return }
        let dict: [String: String] = [
            "sdp": candidate.sdp,
            "sdpMLineIndex": "\(candidate.sdpMLineIndex)",
            "sdpMid": candidate.sdpMid ?? ""
        ]
        if let json = try? JSONSerialization.data(withJSONObject: dict),
           let jsonStr = String(data: json, encoding: .utf8) {
            var payload = "ICE:".data(using: .utf8) ?? Data()
            payload.append(jsonStr.data(using: .utf8) ?? Data())
            onOutgoingSignaling?(payload, entry.key)
        }
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
}

// MARK: - RTCDataChannelDelegate

extension WebRTCService: RTCDataChannelDelegate {
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let entry = dataChannels.first(where: { $0.value == dataChannel }) {
            onDataReceived?(buffer.data, entry.key)
        }
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        log.debug("DataChannel state: \(dataChannel.readyState.rawValue)")
    }
}
