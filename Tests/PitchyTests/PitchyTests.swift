import XCTest
@testable import Pitchy

private func generateSamples(
    freq: Float, size: Int, maxamp: Float = 1,
    offset: Float = 0, sampleRate: Float = 8 * 44100) -> [Float] {
    
    var samples = [Float]()
    for i in 1...size {
        let start = Float(i) + offset
        let x = start * 2 * .pi * (freq / sampleRate)
        let y = sin(x) * maxamp
        samples.append(y)
    }
    
    return samples
}

final class PitchyTests: XCTestCase {
    
    private let sampleRate: Float = 44100
    
    func testNoisegateClose() throws {
        let estimate = Estimate(sampleRate: sampleRate)
        let samples = generateSamples(
            freq: 440, size: 512,
            maxamp: 0.02, offset: 100, sampleRate: sampleRate)
        let pitch = estimate.process(samples)
        XCTAssertNil(pitch)
    }
    
    func testNoisegateOpen() throws {
        let estimate = Estimate(sampleRate: sampleRate)
        let samples = generateSamples(
            freq: 440, size: 512,
            maxamp: 0.03, offset: 50, sampleRate: sampleRate)
        let pitch = estimate.process(samples)
        XCTAssertNotNil(pitch)
    }
    
    func testLowFreq() throws {
        let freq = Float(16.35)
        let estimate = Estimate(sampleRate: sampleRate)
        let samples = generateSamples(
            freq: freq, size: 32 * 1024,
            maxamp: 0.03, offset: 75, sampleRate: sampleRate)
        if let pitch = estimate.process(samples) {
            XCTAssertEqual(pitch, freq, accuracy: 0.25)
        }
        else {
            XCTFail()
        }
    }
    
    func testHighFreq() throws {
        let freq = Float(4186.01)
        let estimate = Estimate(sampleRate: sampleRate)
        let samples = generateSamples(
            freq: freq, size: 512,
            maxamp: 0.03, offset: 150, sampleRate: sampleRate)
        if let pitch = estimate.process(samples) {
            XCTAssertEqual(pitch, freq, accuracy: 0.5)
        }
        else {
            XCTFail()
        }
    }

    static var allTests = [
        ("Basic", testNoisegateClose, testNoisegateOpen),
    ]
}
