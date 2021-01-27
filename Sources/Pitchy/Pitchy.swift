import AudioToolbox
import AVFoundation

extension OSStatus {
    func noErrOr(error: Error) throws {
        if self != noErr {
            print("OSStatus Error: \(self)")
            throw error
        }
    }
}

extension Optional {
    func unwrapOr(error: Error) throws -> Wrapped {
        if let value = self {
            return value
        }
        else {
            throw error
        }
    }
}

extension Data {
    func elements<T>() -> [T] {
        return self.withUnsafeBytes { ptr in
            let start = ptr.baseAddress?.assumingMemoryBound(to: T.self)
            let buffer = UnsafeBufferPointer(start: start,
                                             count: self.count / MemoryLayout<T>.size)
            return Array<T>(buffer)
        }
    }
}

public enum PitchyError: Error {
    case auInitFail
    case auDeinitFail
    case auStartFail
    case auStopFail
}

public class Pitchy {
    public typealias FreqUpdate = (_ freq: Double?) -> Void
    
    fileprivate let ioUnit: AudioUnit
    fileprivate let comp: AudioComponent
    fileprivate var isRunning: Bool
    fileprivate var update: FreqUpdate?
    fileprivate var overlap: Data
    
    public init() throws {
        isRunning = false
        overlap = Data()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(AVAudioSession.Category.record, mode: AVAudioSession.Mode.spokenAudio)
        
        var compDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        comp = try AudioComponentFindNext(nil, &compDesc)
            .unwrapOr(error: PitchyError.auInitFail)
        
        var ioUnitTmp: AudioComponentInstance?
        try AudioComponentInstanceNew(comp, &ioUnitTmp)
            .noErrOr(error: PitchyError.auInitFail)
        
        guard let ioUnitLocal = ioUnitTmp else {
            throw PitchyError.auInitFail
        }
        
        ioUnit = ioUnitLocal
        
        var flag = UInt32(1)
        try AudioUnitSetProperty(
            ioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &flag,
            UInt32(MemoryLayout<UInt32>.size))
            .noErrOr(error: PitchyError.auInitFail)
        
        var asbd = AudioStreamBasicDescription(
            mSampleRate: session.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0)
        try AudioUnitSetProperty(
            ioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
            .noErrOr(error: PitchyError.auInitFail)
        
        var callbackStruct = AURenderCallbackStruct(
            inputProc: recordingCallback,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        try AudioUnitSetProperty(
            ioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            1,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size))
            .noErrOr(error: PitchyError.auInitFail)
        
        try AudioUnitInitialize(ioUnit)
            .noErrOr(error: PitchyError.auInitFail)
    }

    public func start(update _update: @escaping FreqUpdate) throws {
        update = _update
        if !isRunning {
            isRunning = true
            try AudioOutputUnitStart(ioUnit)
                .noErrOr(error: PitchyError.auStartFail)
        }
    }

    public func stop() throws {
        if isRunning {
            try AudioOutputUnitStop(ioUnit)
                .noErrOr(error: PitchyError.auStopFail)
            isRunning = false
        }
    }

    deinit {
        do {
            try stop()
            try AudioUnitUninitialize(ioUnit)
                .noErrOr(error: PitchyError.auDeinitFail)
            try AudioComponentInstanceDispose(comp)
                .noErrOr(error: PitchyError.auDeinitFail)
        }
        catch {
            print("An error occured during AU deinit")
        }
    }
    
    fileprivate func noisegate(_ data: Data, release: Float, threshold: Float) -> Bool {
        var releaseRatio = Float(1.0)
        var releaseSpeed = Float(1.0)
        var gateState = false
        
        if release != 0 {
            releaseSpeed = 1.0/release
        }
        
        let elements: [Float32] = data.elements()
        for sample in elements {
            if fabsf(sample) < threshold {
                if gateState {
                    releaseRatio -= releaseSpeed
                    if (releaseRatio <= 0) {
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
    
    fileprivate func process(_ data: Data) {
        if noisegate(data, release: 50.0, threshold: 0.02) {
            update?(20)
        }
    }
}

func recordingCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
{
    let `self` = unsafeBitCast(inRefCon, to: Pitchy.self)
    var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: 1024,
                mData: nil))
    var status = noErr
    
    status = AudioUnitRender(self.ioUnit,
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &bufferList)
    
    if status != noErr {
        return status
    }
    
    if let data = bufferList.mBuffers.mData {
        let size = bufferList.mBuffers.mDataByteSize
        let data = Data(
            bytes:  data,
            count: Int(size))
        DispatchQueue.main.async {
            self.process(data)
        }
    }
    
    return status
}
