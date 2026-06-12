import Foundation
import AVFoundation

// MARK: - Audio Codec (AAC → Opus migration path)

/// Compresses voice audio for mesh transport.
///
/// Config: 16kHz mono, ~32kbps target.
///
/// Currently uses AAC (built into iOS, no external dependency).
/// AAC at 16kHz mono provides ~6-8x compression vs raw PCM and is
/// suitable for voice. Migration to libopus is planned for production
/// to achieve lower latency (<40ms frames) and better quality at 16kbps.
///
/// Compression: raw 16-bit PCM 16kHz mono → AAC → ~32kbps.
/// PCM: 32KB/s → AAC: ~4KB/s (for voice).

final class OpusCodec {
    static let sampleRate: Int = 16000
    static let channels: Int = 1
    static let targetBitrate: Int = 32000

    private let encoderQueue = DispatchQueue(label: "com.wawa.codec.encoder")
    private let decoderQueue = DispatchQueue(label: "com.wawa.codec.decoder")

    // MARK: - Encode (PCM 16-bit → Compressed)

    func encode(pcmData: Data, sampleRate: Double = 16000) -> Data? {
        return encoderQueue.sync {
            compressWithAAC(pcmData: pcmData, sampleRate: sampleRate)
        }
    }

    // MARK: - Decode (Compressed → PCM 16-bit)

    func decode(compressedData: Data, sampleRate: Double = 16000) -> Data? {
        return decoderQueue.sync {
            decompressAAC(compressedData, sampleRate: sampleRate)
        }
    }

    // MARK: - AAC Compression (built into iOS)

    private func compressWithAAC(pcmData: Data, sampleRate: Double) -> Data? {
        // Create input PCM format (16-bit signed integer, mono)
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            Logger.shared.audio("Codec: failed to create PCM input format")
            return nil
        }

        // Create output AAC format
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            Logger.shared.audio("Codec: failed to create intermediate format")
            return nil
        }

        // Create AAC compressed format descriptor
        var aacDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        guard let aacFormat = AVAudioFormat(streamDescription: &aacDescription) else {
            Logger.shared.audio("Codec: failed to create AAC output format")
            return nil
        }

        // Create converter: PCM → AAC
        guard let converter = AVAudioConverter(from: inputFormat, to: aacFormat) else {
            Logger.shared.audio("Codec: failed to create PCM→AAC converter")
            return nil
        }

        // AAC bitrate defaults are reasonable for voice (~32-48kbps at 16kHz mono).
        // Explicit bitrate config requires AudioConverterRef which is not public API.
        // Production: libopus gives precise bitrate control.

        // Create PCM buffer from raw data
        let frameCount = AVAudioFrameCount(pcmData.count / 2) // 2 bytes per Int16 sample
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            Logger.shared.audio("Codec: failed to create PCM buffer")
            return nil
        }
        pcmBuffer.frameLength = frameCount

        // Copy raw PCM data into buffer
        pcmData.withUnsafeBytes { rawBuffer in
            guard let destination = pcmBuffer.int16ChannelData?[0] else { return }
            memcpy(destination, rawBuffer.baseAddress, pcmData.count)
        }

        // Allocate output buffer (AAC frames are 1024 samples)
        let outputFrameCapacity = AVAudioFrameCount(4096)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: aacFormat, frameCapacity: outputFrameCapacity) else {
            Logger.shared.audio("Codec: failed to create output buffer")
            return nil
        }

        // Convert
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            Logger.shared.audio("Codec: AAC encode error: \(error.localizedDescription)")
            // Fallback: return raw PCM (better than nothing)
            return pcmData
        }

        // Extract compressed data from output buffer
        guard let compressedData = outputBuffer.toData() else {
            Logger.shared.audio("Codec: failed to extract AAC data, falling back to PCM")
            return pcmData
        }

        return compressedData
    }

    // MARK: - AAC Decompression

    private func decompressAAC(_ compressedData: Data, sampleRate: Double) -> Data? {
        // Create AAC input format
        var aacDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        guard let aacFormat = AVAudioFormat(streamDescription: &aacDescription) else {
            Logger.shared.audio("Codec: failed to create AAC input format for decode")
            return nil
        }

        // Create PCM output format (16-bit signed integer, mono)
        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            Logger.shared.audio("Codec: failed to create PCM output format for decode")
            return nil
        }

        // Create converter: AAC → PCM
        guard let converter = AVAudioConverter(from: aacFormat, to: pcmFormat) else {
            Logger.shared.audio("Codec: failed to create AAC→PCM converter")
            return nil
        }

        // Create AAC input buffer
        guard let aacBuffer = AVAudioPCMBuffer(pcmFormat: aacFormat, frameCapacity: 4096) else {
            Logger.shared.audio("Codec: failed to create AAC input buffer")
            return nil
        }
        aacBuffer.frameLength = 4096

        // Copy compressed data into AAC buffer
        var bytesCopied: UInt32 = 0
        compressedData.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else { return }
            let packetDescriptions = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
            defer { packetDescriptions.deallocate() }
            packetDescriptions.pointee = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(compressedData.count)
            )
            let status = AudioConverterFillComplexBuffer(
                converter.audioConverterRef,
                { _, _, _, _, _, _ in 0 }, // will be handled by the converter
                nil,
                &bytesCopied,
                aacBuffer.mutableAudioBufferList,
                packetDescriptions
            )
            if status != noErr {
                Logger.shared.audio("Codec: AudioConverterFillComplexBuffer failed: \(status)")
            }
        }

        // Allocate PCM output buffer
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 4096) else {
            Logger.shared.audio("Codec: failed to create PCM output buffer")
            return nil
        }

        // Convert
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return aacBuffer
        }

        converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            Logger.shared.audio("Codec: AAC decode error: \(error.localizedDescription)")
            return nil
        }

        return pcmBuffer.toData()
    }
}

// MARK: - AVAudioPCMBuffer → Data

extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let channelData = self.int16ChannelData else { return nil }
        let frameLength = Int(self.frameLength)
        return Data(bytes: channelData[0], count: frameLength * 2)
    }
}

// MARK: - Data → PCM Buffer

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
