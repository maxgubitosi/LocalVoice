import AVFoundation
import OSLog

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var isRecording = false
    private let targetSampleRate: Double = 16000
    // Serializes access to `samples` and `isRecording` across the audio thread and main thread.
    private let queue = DispatchQueue(label: "com.localvoice.audiocapture")

    func startRecording() {
        var shouldProceed = false
        queue.sync {
            guard !isRecording else { return }
            samples = []
            isRecording = true
            shouldProceed = true
        }
        guard shouldProceed else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat()) else {
            Logger.audio.error("Failed to create audio converter")
            queue.sync { isRecording = false }
            return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer: buffer, using: converter)
        }

        do {
            try engine.start()
        } catch {
            Logger.audio.error("Engine start error: \(error)")
            input.removeTap(onBus: 0)
            queue.sync { isRecording = false }
        }
    }

    func stopRecording(completion: @escaping ([Float]?) -> Void) {
        var captured: [Float]? = nil
        var wasRecording = false
        queue.sync {
            wasRecording = isRecording
            if isRecording {
                isRecording = false
                captured = samples.isEmpty ? nil : samples
            }
        }
        guard wasRecording else {
            completion(nil)
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        completion(captured)
    }

    // MARK: - Private

    private func convert(buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        let outputFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: whisperFormat(),
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let err = error {
            Logger.audio.error("Conversion error: \(err)")
            return
        }

        guard let channelData = output.floatChannelData else { return }
        let frameCount = Int(output.frameLength)
        // Copy while output is still in scope — channelData[0] is a raw pointer into output's
        // buffer and becomes a dangling pointer once output is released by ARC.
        let floatData = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        // queue.async serializes sample writes against stopRecording's queue.sync read.
        // engine.stop() flushes pending callbacks before returning, so no samples are lost.
        queue.async { [weak self] in
            self?.samples.append(contentsOf: floatData)
        }
    }

    private func whisperFormat() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
    }
}
