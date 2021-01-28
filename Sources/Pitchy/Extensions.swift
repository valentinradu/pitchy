import AudioToolbox

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
        return withUnsafeBytes { ptr in
            let start = ptr.baseAddress?.assumingMemoryBound(to: T.self)
            let buffer = UnsafeBufferPointer(start: start,
                                             count: self.count / MemoryLayout<T>.size)
            return [T](buffer)
        }
    }
}
