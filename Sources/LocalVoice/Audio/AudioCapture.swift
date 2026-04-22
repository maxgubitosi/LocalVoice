import AVFoundation

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var isRecording = false
    private let targetSampleRate: Double = 16000

    func startRecording() {
        guard !isRecording else { return }
        samples = []
        isRecording = true

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Converter from native input format → 16 kHz mono Float32 (WhisperKit requirement)
        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat()) else {
            debugLog("[AudioCapture] Failed to create converter")
            return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer: buffer, using: converter)
        }

        do {
            try engine.start()
        } catch {
            debugLog("[AudioCapture] Engine start error: \(error)")
            input.removeTap(onBus: 0)
            isRecording = false
        }
    }

    func stopRecording(completion: @escaping ([Float]?) -> Void) {
        guard isRecording else { completion(nil); return }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let captured = samples
        completion(captured.isEmpty ? nil : captured)
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
            debugLog("[AudioCapture] Conversion error: \(err)")
            return
        }

        guard let channelData = output.floatChannelData else { return }
        let frameCount = Int(output.frameLength)
        samples.append(contentsOf: Array(UnsafeBufferPointer(start: channelData[0], count: frameCount)))
    }

    private func whisperFormat() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
    }
}
