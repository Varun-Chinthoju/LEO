import Foundation

enum IPCFramingError: Error, Equatable {
    case frameTooLarge
    case malformedFrame
    case unsupportedVersion(Int)
}

struct IPCFraming {
    static let maxFrameSize = 1_048_576
    private var buffer = Data()

    static func encode(_ message: IPCMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= maxFrameSize else { throw IPCFramingError.frameTooLarge }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    mutating func append(_ data: Data) throws -> [IPCMessage] {
        buffer.append(data)
        var messages: [IPCMessage] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length <= Self.maxFrameSize else { throw IPCFramingError.frameTooLarge }
            guard buffer.count >= 4 + Int(length) else { break }
            let payload = buffer.subdata(in: 4..<(4 + Int(length)))
            buffer.removeSubrange(0..<(4 + Int(length)))
            do {
                let message = try JSONDecoder().decode(IPCMessage.self, from: payload)
                guard message.version == IPCMessage.currentVersion else { throw IPCFramingError.unsupportedVersion(message.version) }
                messages.append(message)
            } catch let error as IPCFramingError {
                throw error
            } catch {
                throw IPCFramingError.malformedFrame
            }
        }
        return messages
    }
}
