import Accelerate
import AudioToolbox
import AVFoundation

public class Pitchy {
    public typealias FreqUpdate = (_ freq: Float?) -> Void

    private let capture: Capture
    private let estimate: Estimate

    public init() throws {
        capture = try Capture()
        estimate = try Estimate()
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
