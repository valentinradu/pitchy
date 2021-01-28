import Accelerate
import AudioToolbox
import AVFoundation

public class Capture {
    public typealias SamplesUpdate = (_ samples: [Float]) -> Void
    
    fileprivate let ioUnit: AudioUnit
    fileprivate let comp: AudioComponent
    fileprivate let sampleRate: Float
    fileprivate var isRunning: Bool
    fileprivate var update: SamplesUpdate?
    
    public init(sampleRate _sampleRate: Float) throws {
        isRunning = false
        sampleRate = _sampleRate
        
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
            mSampleRate: Double(sampleRate),
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

    public func start(update _update: @escaping SamplesUpdate) throws {
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
}

func recordingCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
{
    let `self` = unsafeBitCast(inRefCon, to: Capture.self)
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
            bytes: data,
            count: Int(size))
        DispatchQueue.main.async {
            let samples: [Float32] = data.elements()
            self.update?(samples)
        }
    }
    
    return status
}
