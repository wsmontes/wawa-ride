import Foundation
@preconcurrency import WebRTC
import os.log

/// Manages WebRTC peer connections. All internal state is protected by a serial queue.
final class WebRTCService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published

    @Published var peers: [String: PeerState] = [:]

    enum PeerState: String { case connecting, connected, failed }

    // MARK: - Properties

    private let factory: RTCPeerConnectionFactory
    private let iceServers: [RTCIceServer]
    private let localRiderID: String
    private let log = Logger(subsystem: "com.wawaride", category: "WebRTC")

    /// Serial queue protecting all mutable state.
    private let queue = DispatchQueue(label: "com.wawaride.webrtc")

    private var connections: [String: RTCPeerConnection] = [:]
    private var dataChannels: [String: RTCDataChannel] = [:]

    /// Track which peers we've already set up to avoid duplicate offers.
    private var pendingSetup: Set<String> = []

    var onDataReceived: ((Data, String) -> Void)?
    var onOutgoingSignaling: ((Data, String) -> Void)?

    // MARK: - Init

    init(localRiderID: String) {
        self.localRiderID = localRiderID
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
        iceServers = servers
        super.init()
        log.info("WebRTC configured (\(servers.count) ICE servers)")
    }

    // MARK: - Public API

    func createOffer(for riderID: String) {
        queue.async { [weak self] in
            guard let self else { return }

            // Guard against duplicate setup
            guard !self.pendingSetup.contains(riderID),
                  self.connections[riderID] == nil
            else {
                self.log.debug("Offer already pending/active for \(riderID)")
                return
            }
            self.pendingSetup.insert(riderID)

            DispatchQueue.main.async {
                self.peers[riderID] = .connecting
            }

            let config = RTCConfiguration()
            config.iceServers = self.iceServers
            config.continualGatheringPolicy = .gatherContinually
            config.sdpSemantics = .unifiedPlan

            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
            )

            guard let pc = self.factory.peerConnection(
                with: config, constraints: constraints, delegate: nil
            ) else {
                self.log.error("Failed to create peer connection for \(riderID)")
                self.pendingSetup.remove(riderID)
                DispatchQueue.main.async { self.peers[riderID] = .failed }
                return
            }

            pc.delegate = self
            self.connections[riderID] = pc

            let dcConfig = RTCDataChannelConfiguration()
            dcConfig.isOrdered = false
            if let dc = pc.dataChannel(forLabel: "wawa-location", configuration: dcConfig) {
                dc.delegate = self
                self.dataChannels[riderID] = dc
            }

            let offerConstraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveAudio": "false",
                    "OfferToReceiveVideo": "false"
                ],
                optionalConstraints: nil
            )

            pc.offer(for: offerConstraints) { [weak self] sdp, error in
                guard let self else { return }
                guard let sdp else {
                    self.log.error("Offer failed for \(riderID): \(error?.localizedDescription ?? "unknown")")
                    self.pendingSetup.remove(riderID)
                    DispatchQueue.main.async { self.peers[riderID] = .failed }
                    return
                }
                pc.setLocalDescription(sdp) { err in
                    if let err { self.log.error("setLocalDescription: \(err.localizedDescription)") }
                }
                if let data = sdp.sdp.data(using: .utf8) {
                    var payload = "OFFER:".data(using: .utf8) ?? Data()
                    payload.append(data)
                    self.onOutgoingSignaling?(payload, riderID)
                }
            }
        }
    }

    func onSignalingReceived(_ data: Data, from riderID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let text = String(data: data, encoding: .utf8) else { return }

            if text.hasPrefix("OFFER:") {
                self.handleOffer(String(text.dropFirst(7)), from: riderID)
            } else if text.hasPrefix("ANSWER:") {
                self.handleAnswer(String(text.dropFirst(7)), from: riderID)
            } else if text.hasPrefix("ICE:") {
                self.handleICECandidate(String(text.dropFirst(4)), from: riderID)
            }
        }
    }

    func send(_ data: Data, to riderID: String) {
        queue.async { [weak self] in
            guard let self, let dc = self.dataChannels[riderID] else {
                self?.log.warning("No DataChannel for \(riderID)")
                return
            }
            dc.sendData(RTCDataBuffer(data: data, isBinary: true))
        }
    }

    func broadcast(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            for (_, dc) in self.dataChannels where dc.readyState == .open {
                dc.sendData(RTCDataBuffer(data: data, isBinary: true))
            }
        }
    }

    func disconnect(peer riderID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.dataChannels[riderID]?.close()
            self.dataChannels.removeValue(forKey: riderID)
            self.connections[riderID]?.close()
            self.connections.removeValue(forKey: riderID)
            self.pendingSetup.remove(riderID)
            DispatchQueue.main.async { self.peers.removeValue(forKey: riderID) }
        }
    }
}

// MARK: - SDP / ICE Handlers

private extension WebRTCService {

    func emptyConstraints() -> RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    }

    func handleOffer(_ sdp: String, from riderID: String) {
        pendingSetup.insert(riderID)
        DispatchQueue.main.async { self.peers[riderID] = .connecting }

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.continualGatheringPolicy = .gatherContinually

        guard let pc = factory.peerConnection(with: config, constraints: emptyConstraints(), delegate: nil) else {
            pendingSetup.remove(riderID)
            DispatchQueue.main.async { self.peers[riderID] = .failed }
            return
        }
        pc.delegate = self
        connections[riderID] = pc

        pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { [weak self] err in
            guard let self else { return }
            if let err { self.log.error("setRemoteDescription: \(err.localizedDescription)") }

            pc.answer(for: self.emptyConstraints()) { answerSDP, error in
                guard let answerSDP else {
                    self.pendingSetup.remove(riderID)
                    DispatchQueue.main.async { self.peers[riderID] = .failed }
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
        connections[riderID]?.setRemoteDescription(
            RTCSessionDescription(type: .answer, sdp: sdp)
        ) { [weak self] err in
            if let self, let err {
                self.log.error("setRemoteDescription answer: \(err.localizedDescription)")
            }
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
            if let self, let err {
                self.log.error("addICE: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ pc: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        guard let entry = connections.first(where: { $0.value == pc }) else { return }
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

    func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let entry = connections.first(where: { $0.value == pc }) else { return }
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

    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCSignalingState) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
}

// MARK: - RTCDataChannelDelegate

extension WebRTCService: RTCDataChannelDelegate {
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let entry = dataChannels.first(where: { $0.value == dataChannel }) {
            onDataReceived?(buffer.data, entry.key)
        }
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        log.debug("DataChannel: \(dataChannel.readyState.rawValue)")
    }
}
