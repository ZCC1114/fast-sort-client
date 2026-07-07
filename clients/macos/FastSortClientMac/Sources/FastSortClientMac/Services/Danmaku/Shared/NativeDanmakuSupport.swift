import CryptoKit
import Foundation
import zlib

struct NativeDanmakuError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

enum NativeDanmakuHTTP {
    static let desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
    static let taobaoMobileUserAgent = "Mozilla/5.0 (Linux; Android 11; Pixel 4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"

    static func firstText(_ payload: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            if let value = payload[key], !(value is NSNull) {
                return "\(value)"
            }
        }
        return fallback
    }

    static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return false
    }

    static func flexibleInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func decodeRepeatedly(_ value: String) -> String {
        var current = value
        for _ in 0..<3 {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            current = decoded
        }
        return current
    }

    static func paddedBase64(_ value: String) -> String {
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    static func sha1Hex(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func md5Hex(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func randomNumericString(length: Int) -> String {
        guard length > 0 else { return "" }
        let first = String(Int.random(in: 1...9))
        guard length > 1 else { return first }
        return first + String((0..<(length - 1)).map { _ in String(Int.random(in: 0...9)) }.joined())
    }

    static func randomToken(length: Int, alphabet: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789=_") -> String {
        let characters = Array(alphabet)
        guard !characters.isEmpty, length > 0 else { return "" }
        return String((0..<length).map { _ in characters.randomElement() ?? "x" })
    }

    static func isGzipPayload(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.index(after: data.startIndex)] == 0x8B
    }

    static func gunzip(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw NativeDanmakuError("gzip 初始化失败: \(initStatus)")
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let bufferSize = 64 * 1024
        var status: Int32 = Z_OK

        try data.withUnsafeBytes { inputBuffer in
            guard let inputBase = inputBuffer.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase)
            stream.avail_in = uInt(data.count)

            repeat {
                var buffer = [UInt8](repeating: 0, count: bufferSize)
                status = buffer.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(bufferSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                let produced = bufferSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }

                if status != Z_OK && status != Z_STREAM_END {
                    throw NativeDanmakuError("gzip 解压失败: \(status)")
                }
            } while status != Z_STREAM_END
        }

        return output
    }

    static func firstRegexMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    static func allRegexMatches(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[valueRange])
        }
    }

    static func queryValue(in text: String, name: String) -> String? {
        if let url = URL(string: text),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == name })?.value {
            return decodeRepeatedly(value)
        }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        if let value = firstRegexMatch(in: text, pattern: "\(escaped)=([^&\"' <>\\n]+)") {
            return decodeRepeatedly(value)
        }
        return nil
    }
}

struct NativeProtoField {
    let number: Int
    let wireType: Int
    let varint: UInt64?
    let data: Data?

    var stringValue: String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension Array where Element == NativeProtoField {
    func firstVarint(_ number: Int) -> UInt64? {
        first { $0.number == number && $0.wireType == 0 }?.varint
    }

    func firstData(_ number: Int) -> Data? {
        first { $0.number == number && $0.wireType == 2 }?.data
    }

    func firstString(_ number: Int) -> String? {
        first { $0.number == number && $0.wireType == 2 }?.stringValue
    }

    func allData(_ number: Int) -> [Data] {
        compactMap { $0.number == number && $0.wireType == 2 ? $0.data : nil }
    }
}

enum SimpleProtobuf {
    static func parseFields(_ data: Data) -> [NativeProtoField] {
        var fields: [NativeProtoField] = []
        var index = data.startIndex
        while index < data.endIndex {
            guard let key = readVarint(data, index: &index) else { break }
            let number = Int(key >> 3)
            let wireType = Int(key & 0x7)
            switch wireType {
            case 0:
                guard let value = readVarint(data, index: &index) else { return fields }
                fields.append(NativeProtoField(number: number, wireType: wireType, varint: value, data: nil))
            case 2:
                guard let length = readVarint(data, index: &index) else { return fields }
                let end = data.index(index, offsetBy: Int(length), limitedBy: data.endIndex) ?? data.endIndex
                guard end <= data.endIndex else { return fields }
                fields.append(NativeProtoField(number: number, wireType: wireType, varint: nil, data: Data(data[index..<end])))
                index = end
            case 5:
                let end = data.index(index, offsetBy: 4, limitedBy: data.endIndex) ?? data.endIndex
                guard end <= data.endIndex else { return fields }
                fields.append(NativeProtoField(number: number, wireType: wireType, varint: nil, data: Data(data[index..<end])))
                index = end
            case 1:
                let end = data.index(index, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
                guard end <= data.endIndex else { return fields }
                fields.append(NativeProtoField(number: number, wireType: wireType, varint: nil, data: Data(data[index..<end])))
                index = end
            default:
                return fields
            }
        }
        return fields
    }

    static func varintField(_ fieldNumber: Int, _ value: UInt64) -> Data {
        var data = encodeVarint(UInt64(fieldNumber << 3))
        data.append(encodeVarint(value))
        return data
    }

    static func lengthField(_ fieldNumber: Int, _ payload: Data) -> Data {
        var data = encodeVarint(UInt64((fieldNumber << 3) | 2))
        data.append(encodeVarint(UInt64(payload.count)))
        data.append(payload)
        return data
    }

    static func stringField(_ fieldNumber: Int, _ value: String) -> Data {
        lengthField(fieldNumber, Data(value.utf8))
    }

    private static func readVarint(_ data: Data, index: inout Data.Index) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex && shift < 64 {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        return nil
    }

    private static func encodeVarint(_ value: UInt64) -> Data {
        var value = value
        var data = Data()
        while value >= 0x80 {
            data.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
        return data
    }
}
