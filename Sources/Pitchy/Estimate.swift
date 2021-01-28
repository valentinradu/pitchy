import Accelerate
import AudioToolbox
import AVFoundation

public class Estimate {
    
    private let sampleRate: Float
    
    public init(sampleRate _sampleRate: Float) {
        sampleRate = _sampleRate
    }
    
    fileprivate func noisegate(_ samples: [Float], release: Float, threshold: Float) -> Bool {
        var releaseRatio = Float(1.0)
        var releaseSpeed = Float(1.0)
        var gateState = false
        
        if release != 0 {
            releaseSpeed = 1.0 / release
        }
        
        for sample in samples {
            if fabsf(sample) < threshold {
                if gateState {
                    releaseRatio -= releaseSpeed
                    if releaseRatio <= 0 {
                        releaseRatio = 0
                        gateState = false
                    }
                }
            }
            else {
                releaseRatio = 1
                gateState = true
            }
        }
        
        return gateState
    }
    
    fileprivate func hamming(_ samples: [Float]) -> [Float] {
        var original = samples
        var result = samples
        var window = [Float](repeating: 0, count: samples.count)
        vDSP_hann_window(
            &window,
            vDSP_Length(window.count),
            Int32(vDSP_HANN_NORM))
        
        vDSP_vmul(&original, 1, window, 1, &result, 1, vDSP_Length(window.count))
        
        return result
    }
    
    fileprivate func alignPhases(_ samples: [Float]) -> [Float] {
        let halfcount = samples.count / 2
        guard let ffft = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(samples.count),
            vDSP_DFT_Direction.FORWARD)
        else {
            return []
        }
        guard let ifft = vDSP_DFT_zrop_CreateSetup(
            ffft,
            vDSP_Length(samples.count),
            vDSP_DFT_Direction.INVERSE)
        else {
            return []
        }
        
        var ri = [Float](repeating: 0.0, count: halfcount)
        var ii = [Float](repeating: 0.0, count: halfcount)
        var ro = [Float](repeating: 0.0, count: halfcount)
        var io = [Float](repeating: 0.0, count: halfcount)
        
        return samples.withUnsafeBufferPointer { sb in
            
            io.withUnsafeMutableBufferPointer { iob in
                ro.withUnsafeMutableBufferPointer { rob in
                    ii.withUnsafeMutableBufferPointer { iib in
                        ri.withUnsafeMutableBufferPointer { rib in
                            guard let sba = sb.baseAddress else { return [] }
                            guard let iiba = iib.baseAddress else { return [] }
                            guard let riba = rib.baseAddress else { return [] }
                            guard let roba = rob.baseAddress else { return [] }
                            guard let ioba = iob.baseAddress else { return [] }
                        
                            cblas_scopy(Int32(halfcount), sba, 2, riba, 1)
                            cblas_scopy(Int32(halfcount), sba.advanced(by: 1), 2, iiba, 1)
                        
                            vDSP_DFT_Execute(ffft, riba, iiba, roba, ioba)
                                
                            var split = DSPSplitComplex(
                                realp: roba,
                                imagp: ioba)
                                
                            vDSP_zvmags(&split, 1, riba, 1, vDSP_Length(halfcount))
                            vDSP_vclr(iiba, 1, vDSP_Length(halfcount))
                                
                            vDSP_DFT_Execute(ifft, riba, iiba, roba, ioba)

                            var result = [Float](repeating: 0.0, count: samples.count)
                            
                            result.withUnsafeMutableBufferPointer { rb in
                                if let rba = rb.baseAddress {
                                    let cba = UnsafeMutableRawPointer(rba)
                                        .bindMemory(to: DSPComplex.self, capacity: rb.count)
                                    vDSP_ztoc(&split, 1, cba, 2, vDSP_Length(halfcount))
                                    var scale = 1.0 / (rb.first ?? 1)
                                    vDSP_vsmul(rba, 1, &scale, rba, 1, vDSP_Length(samples.count))
                                }
                            }
                            
                            return result
                        }
                    }
                }
            }
        }
    }
    
    fileprivate func peakPicking(_ samples: [Float]) -> [Int] {
        let halfcount = samples.count / 2 - 1
        var pos = 0
        var curMaxPos = 0
        var maximas = [Int]()
        
        // find the first negative zero crossing
        while pos < halfcount, samples[pos] > 0 {
            pos += 1
        }

        // loop over all the values below zero
        while pos < halfcount, samples[pos] <= 0.0 {
            pos += 1
        }
        
        if pos == 0 {
            pos = 1
        }

        while pos < halfcount {
            if samples[pos] > samples[pos - 1], samples[pos] >= samples[pos + 1] {
                if curMaxPos == 0 {
                    // the first max (between zero crossings)
                    curMaxPos = pos
                }
                else if samples[pos] > samples[curMaxPos] {
                    // a higher max (between the zero crossings)
                    curMaxPos = pos
                }
            }
            pos += 1
            // a negative zero crossing
            if pos < halfcount, samples[pos] <= 0 {
                // if there was a maximum add it to the list of maxima
                if curMaxPos > 0 {
                    maximas.append(curMaxPos)
                    // clear the maximum position, so we start looking for a new one
                    curMaxPos = 0
                }
                while pos < halfcount, samples[pos] <= 0 {
                    pos += 1 // loop over all the values below zero
                }
            }
        }
        
        // if there was a maximum in the last part
        if curMaxPos > 0 {
            maximas.append(curMaxPos)
        }

        return maximas
    }
    
    fileprivate func parabolicInterpolation(_ bins: [Float], peak: Int) -> (Float, Float) {
        let nsdfa = bins[peak - 1]
        let nsdfb = bins[peak]
        let nsdfc = bins[peak + 1]
        let bval = peak
        let bottom = nsdfc + nsdfa - 2 * nsdfb
        
        if bottom == 0 {
            return (Float(bval), Float(nsdfb))
        }
        else {
            let delta = nsdfa - nsdfc
            return (
                Float(Float(bval) + delta / (2 * bottom)),
                Float(nsdfb - delta * delta / (8 * bottom)))
        }
    }

    fileprivate func estimatePitch(_ bins: [Float], peaks: [Int]) -> Float? {
        var highestAmplitude = -Float.greatestFiniteMagnitude
        var turningPoints = [(Float, Float)]()
        
        for peak in peaks {
            // make sure every annotation has a probability attached
            highestAmplitude = fmax(highestAmplitude, bins[peak])

            if bins[peak] > 0.75 {
                // calculates turningPointX and Y
                let tp = parabolicInterpolation(bins, peak: peak)
                turningPoints.append(tp)

                // remember the highest amplitude
                highestAmplitude = fmax(highestAmplitude, tp.1)
            }
        }

        if turningPoints.count == 0 {
            return nil
        }
        else {
            // use the overall maximum to calculate a cutoff.
            // The cutoff value is based on the highest value and a relative
            // threshold.
            let actualCutoff = 0.99 * highestAmplitude

            // find first period above or equal to cutoff
            guard let periodIndex = turningPoints
                .firstIndex(where: { $0.1 >= actualCutoff })
            else {
                return nil
            }

            let period = turningPoints[periodIndex].0
            let pitchEstimate = sampleRate / period
            if pitchEstimate > 0, pitchEstimate <= sampleRate / 2.0 {
                return pitchEstimate
            }
            else {
                return nil
            }
        }
    }
    
    public func process(_ samples: [Float]) -> Float? {
        if noisegate(samples, release: 50.0, threshold: 0.02) {
            let windowed = hamming(samples)
            let bins = alignPhases(windowed)
            let peaks = peakPicking(bins)
            return estimatePitch(bins, peaks: peaks)
        }
        return nil
    }
}
