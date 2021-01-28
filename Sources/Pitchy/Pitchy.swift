import Accelerate
import AudioToolbox
import AVFoundation

public class Pitchy {
    public typealias FreqUpdate = (_ freq: Float?) -> Void

    private let capture: Capture
    private let estimate: Estimate

    public init() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(AVAudioSession.Category.record, mode: AVAudioSession.Mode.spokenAudio)
        let sampleRate = Float(session.sampleRate)
        capture = try Capture(sampleRate: sampleRate)
        estimate = Estimate(sampleRate: sampleRate)
    }

    public func start(update: @escaping FreqUpdate) throws {
        try capture.start { samples in
            if let pitch = self.estimate.process(samples) {
                update(pitch)
            }
        }
    }

    public func stop() throws {
        try capture.stop()
    }
}
