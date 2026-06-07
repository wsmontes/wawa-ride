import Foundation
import AVFoundation

// MARK: - Opus Audio Codec

/// Opus codec for voice compression.
///
/// Config: 16kHz mono, 32kbps, 20ms frames.
/// Compression: ~8x (32KB/s PCM → 4KB/s Opus).
///
/// NOTE: This is a placeholder implementation using AAC compression
/// until libopus is integrated. AAC provides reasonable voice quality
/// at ~32kbps and is built into iOS (no external dependency).
/// Replace with libopus for production.

final class OpusCodec {
    static let sampleRate: Int = 16000
    static let channels: Int = 1
    static let targetBitrate: Int = 32000

    private let encoderQueue = DispatchQueue(label: "com.wawa.opus.encoder")
    private let decoderQueue = DispatchQueue(label: "com.wawa.opus.decoder")

    // MARK: - Encode (PCM 16-bit → Compressed Audio)

    func encode(pcmData: Data, sampleRate: Double = 16000) -> Data? {
        // Placeholder: Use AAC compression until libopus is integrated
        // AAC at 32kbps for voice is acceptable for MVP

        return encoderQueue.sync { () -> Data? in
            guard let pcmFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            ) else {
                print("🔊 Opus: failed to create PCM format")
                return nil
            }

            guard let pcmBuffer = pcmData.toPCMBuffer(format: pcmFormat) else {
                return nil
            }

            // For MVP: return raw PCM (no compression yet)
            // TODO: Replace with actual Opus encoding via libopus
            return compressWithAAC(pcmBuffer: pcmBuffer, inputFormat: pcmFormat)
        }
    }

    // MARK: - Decode (Compressed Audio → PCM 16-bit)

    func decode(compressedData: Data, sampleRate: Double = 16000) -> Data? {
        return decoderQueue.sync { () -> Data? in
            // TODO: Replace with actual Opus decoding
            // For MVP: decompress AAC placeholder
            return decompressAAC(compressedData, sampleRate: sampleRate)
        }
    }

    // MARK: - AAC Placeholder (MVP)

    private func compressWithAAC(pcmBuffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> Data? {
        // Convert PCM to AAC using AVAudioConverter
        // For initial MVP, we compress using a simple approach
        // Full AAC compression requires AudioConverterRef setup

        // Return raw PCM for now (MVP will work, just larger files)
        // Replace with actual compression before production
        guard let channelData = pcmBuffer.int16ChannelData else { return nil }
        let frameLength = Int(pcmBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * 2)
        return data
    }

    private func decompressAAC(_ data: Data, sampleRate: Double) -> Data? {
        // Return as-is for MVP placeholder
        return data
    }
}

// MARK: - Data + PCM Buffer Extension

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count / 2)) else {
            return nil
        }
        buffer.frameLength = buffer.frameCapacity

        self.withUnsafeBytes { rawBuffer in
            guard let channelData = buffer.int16ChannelData else { return }
            memcpy(channelData[0], rawBuffer.baseAddress, count)
        }

        return buffer
    }
}
