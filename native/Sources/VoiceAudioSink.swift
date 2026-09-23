@preconcurrency import AVFoundation
import Foundation
import os

/// A bounded copy of recent microphone samples, written from the audio thread
/// and read from anywhere else.
///
/// The transcriber's tap is the only tap the engine allows, so voice
/// attribution cannot install its own. It takes a copy here instead. Every
/// rule the transcription path learned the hard way applies: the render thread
/// never waits for this lock, never allocates, and a dropped buffer is always
/// preferable to a stalled one.
final class VoiceAudioSink: @unchecked Sendable {
    private struct Storage {
        var samples: [Float]
        var writeIndex = 0
        var filled = 0
        var sampleRate: Double = 0

        mutating func append(
            _ channel: UnsafePointer<Float>,
            frames: Int,
            stride: Int
        ) {
            guard !samples.isEmpty else { return }
            let capacity = samples.count
            for frame in 0..<frames {
                samples[writeIndex] = channel[frame * stride]
                writeIndex = (writeIndex + 1) % capacity
            }
            filled = min(capacity, filled + frames)
        }

        /// Returns what has accumulated, oldest first, and empties the buffer.
        mutating func take() -> [Float] {
            guard filled > 0 else { return [] }
            let capacity = samples.count
            let start = (writeIndex - filled + capacity) % capacity
            var drained = [Float]()
            drained.reserveCapacity(filled)
            for offset in 0..<filled {
                drained.append(samples[(start + offset) % capacity])
            }
            filled = 0
            return drained
        }
    }

    /// Enough headroom that a slow drain loses nothing at ordinary rates.
    static let bufferedSeconds: Double = 12

    private let storage: OSAllocatedUnfairLock<Storage>

    init(bufferedSeconds: Double = VoiceAudioSink.bufferedSeconds, sampleRate: Double = 48_000) {
        let capacity = max(1_024, Int((bufferedSeconds * sampleRate).rounded()))
        storage = OSAllocatedUnfairLock(
            uncheckedState: Storage(samples: [Float](repeating: 0, count: capacity))
        )
    }

    /// Records the rate the tap will deliver, so the audio thread never has to
    /// ask the buffer for its format.
    func prepare(sampleRate: Double) {
        storage.withLockUnchecked { state in
            state.sampleRate = sampleRate
            state.writeIndex = 0
            state.filled = 0
        }
    }

    /// Called on AVAudioEngine's render thread.
    func receive(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let stride = buffer.stride
        // Skipping a buffer costs a moment of attribution. Waiting costs audio.
        _ = storage.withLockIfAvailableUnchecked { state -> Bool in
            state.append(channel, frames: frames, stride: stride)
            return true
        }
    }

    /// Everything buffered since the last drain, with the rate it was captured at.
    func drain() -> (samples: [Float], sampleRate: Double) {
        storage.withLockUnchecked { state in
            (state.take(), state.sampleRate)
        }
    }

    func reset() {
        storage.withLockUnchecked { state in
            state.writeIndex = 0
            state.filled = 0
        }
    }
}

/// Turns captured microphone samples into the rate the voice model expects.
///
/// Live audio needs none of this, because the model is told the source rate and
/// resamples itself. Enrollment does: the profile is stored at the model's own
/// rate so it never has to be converted again.
enum VoiceAudioResampler {
    static func convert(_ samples: [Float], from input: Double, to output: Double) -> [Float] {
        guard !samples.isEmpty, input > 0, output > 0 else { return [] }
        guard abs(input - output) > 1 else { return samples }
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: input,
            channels: 1,
            interleaved: false
        ),
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: output,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
            let source = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channel = source.floatChannelData?[0]
        else { return [] }

        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }

        let capacity = AVAudioFrameCount((Double(samples.count) * output / input).rounded(.up)) + 4_096
        guard let destination = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else { return [] }

        var delivered = false
        var conversionError: NSError?
        converter.convert(to: destination, error: &conversionError) { _, status in
            if delivered {
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return source
        }
        guard conversionError == nil,
              let converted = destination.floatChannelData?[0],
              destination.frameLength > 0
        else { return [] }
        return Array(UnsafeBufferPointer(start: converted, count: Int(destination.frameLength)))
    }
}
