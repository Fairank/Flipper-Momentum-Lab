import Foundation
import ClassicRecovery

/// Two independent reader authentications from Flipper's .mfkey32.log format.
/// A card dump alone does not contain these exchanges.
public struct ClassicSample: Equatable, Sendable {
    public let sector: Int
    public let keyType: String
    public let cuid: UInt32
    public let nt0: UInt32
    public let nr0: UInt32
    public let ar0: UInt32
    public let nt1: UInt32
    public let nr1: UInt32
    public let ar1: UInt32

    public static let maxSamples = 64
    public static func parse(_ text: String) throws -> [ClassicSample] {
        guard text.utf8.count <= NFCKeyDictionary.maxBytes else { throw RPCError.tooLarge }
        let normalized = (text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var samples: [ClassicSample] = []
        for (offset, line) in normalized.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let fields = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            func invalid(_ reason: String) -> RPCError {
                .message("样本第 \(offset + 1) 行：\(reason)")
            }
            let labels = ["Sec", "key", "cuid", "nt0", "nr0", "ar0", "nt1", "nr1", "ar1"]
            guard fields.count == 18, labels.indices.allSatisfy({ fields[$0 * 2] == labels[$0] }) else {
                throw invalid("需要 Flipper 的 .mfkey32.log 格式，包含同一卡片的两组认证数据。")
            }
            guard fields[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let sector = Int(fields[1]), (0..<40).contains(sector),
                  fields[3] == "A" || fields[3] == "B" else {
                throw invalid("扇区应为 0–39，密钥类型应为 A 或 B。")
            }
            var words: [UInt32] = []
            for i in stride(from: 5, through: 17, by: 2) {
                guard fields[i].utf8.count == 8,
                      fields[i].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                      let word = UInt32(fields[i], radix: 16) else {
                    throw invalid("\(fields[i - 1]) 必须为 8 位十六进制数字。")
                }
                words.append(word)
            }
            guard words[1] != words[4] || words[2] != words[5] else {
                throw invalid("两组认证数据重复，不能用于独立复核。")
            }
            let sample = ClassicSample(sector: sector, keyType: fields[3], cuid: words[0],
                nt0: words[1], nr0: words[2], ar0: words[3], nt1: words[4], nr1: words[5], ar1: words[6])
            if !samples.contains(sample) {
                guard samples.count < maxSamples else { throw invalid("一次最多处理 \(maxSamples) 组样本。") }
                samples.append(sample)
            }
        }
        guard !samples.isEmpty else { throw RPCError.message("没有找到可分析的 MIFARE Classic 认证样本。") }
        return samples
    }

    /// Confirms a supplied candidate against BOTH exchanges, without contacting a card/reader.
    public func matches(key: UInt64) -> Bool {
        guard key < (1 << 48) else { return false }
        return expectedResponse(key: key, nonce: nt0, reader: nr0) == ar0 &&
            expectedResponse(key: key, nonce: nt1, reader: nr1) == ar1
    }

    private func expectedResponse(key: UInt64, nonce: UInt32, reader: UInt32) -> UInt32 {
        var cipher = ClassicCipher(key: key)
        _ = cipher.word(cuid ^ nonce, encrypted: false)
        _ = cipher.word(reader, encrypted: true)
        return cipher.word(0, encrypted: false) ^ ClassicCipher.successor(nonce)
    }
}

public struct ClassicMatch: Equatable, Sendable {
    public let sample: ClassicSample
    public let key: String?
}

public struct ClassicProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let matchedSamples: Int
}

public enum ClassicOffline {
    /// MFKey32/Moebius recovery from two imported authentication exchanges. Scratch allocation
    /// is 17 MiB per sample, with no global lookup table and no initialization work at app launch.
    /// C state recovery is followed by an independent Swift forward check of both exchanges.
    public static func recover(samples: [ClassicSample],
        progress: @escaping @Sendable (ClassicProgress) async -> Void = { _ in }) async throws -> [ClassicMatch] {
        guard !samples.isEmpty, samples.count <= ClassicSample.maxSamples else { throw RPCError.malformed }
        var results: [ClassicMatch] = []
        var matched = 0
        for (index, sample) in samples.enumerated() {
            try Task.checkCancellation()
            await progress(ClassicProgress(completed: index, total: samples.count, matchedSamples: matched))
            let words = [sample.cuid, sample.nt0, sample.nr0, sample.ar0, sample.nt1, sample.nr1, sample.ar1]
            var key: UInt64 = 0
            let status = words.withUnsafeBufferPointer { buffer in
                fl_classic_recover(buffer.baseAddress, &key, { _ in Task<Never, Never>.isCancelled }, nil)
            }
            try Task.checkCancellation()
            switch status {
            case 1:
                guard sample.matches(key: key) else { throw RPCError.message("恢复结果未通过独立复核，未保存密钥。") }
                matched += 1
                results.append(ClassicMatch(sample: sample, key: String(format: "%012llX", key)))
            case 0: results.append(ClassicMatch(sample: sample, key: nil))
            case -1: throw CancellationError()
            case -2: throw RPCError.message("手机可用内存不足，未完成本次密钥恢复。")
            default: throw RPCError.message("本组样本超出计算限制，请检查样本格式和来源。")
            }
            await progress(ClassicProgress(completed: index + 1, total: samples.count, matchedSamples: matched))
            await Task.yield()
        }
        return results
    }

    /// CPU work runs on the generic executor, not SwiftUI's main actor. Cancellation is checked
    /// at most every 64 keys. A non-match means absent from this dictionary, not an unbreakable card.
    public static func verify(samples: [ClassicSample], dictionary: NFCKeyDictionary,
        progress: @escaping @Sendable (ClassicProgress) async -> Void = { _ in }) async throws -> [ClassicMatch] {
        guard !samples.isEmpty, samples.count <= ClassicSample.maxSamples else { throw RPCError.malformed }
        let keys = dictionary.keys.map { UInt64($0, radix: 16)! } // parser establishes 48-bit hex
        let total = samples.count * keys.count
        var result: [ClassicMatch] = []
        var matched = 0
        for (sampleIndex, sample) in samples.enumerated() {
            var found: String?
            for (keyIndex, key) in keys.enumerated() {
                if keyIndex % 64 == 0 {
                    try Task.checkCancellation()
                    if keyIndex % 1024 == 0 {
                        await progress(ClassicProgress(completed: sampleIndex * keys.count + keyIndex,
                            total: total, matchedSamples: matched))
                        await Task.yield()
                    }
                }
                if sample.matches(key: key) { found = dictionary.keys[keyIndex]; matched += 1; break }
            }
            result.append(ClassicMatch(sample: sample, key: found))
            try Task.checkCancellation()
            await progress(ClassicProgress(completed: (sampleIndex + 1) * keys.count, total: total, matchedSamples: matched))
        }
        return result
    }
}

/// Forward Crypto1 operations used by lib/nfc/helpers/crypto1.c, originally from Proxmark3.
/// No state-recovery routine or RF reader operation is included here.
private struct ClassicCipher {
    var odd: UInt32 = 0
    var even: UInt32 = 0
    init(key: UInt64) {
        for i in stride(from: 47, through: 1, by: -2) {
            odd = odd << 1 | UInt32((key >> ((i - 1) ^ 7)) & 1)
            even = even << 1 | UInt32((key >> (i ^ 7)) & 1)
        }
    }
    private var filter: UInt32 {
        var n: UInt32 = (0xf22c0 >> (odd & 15)) & 16
        n |= (0x6c9c0 >> ((odd >> 4) & 15)) & 8
        n |= (0x3c8b0 >> ((odd >> 8) & 15)) & 4
        n |= (0x1e458 >> ((odd >> 12) & 15)) & 2
        n |= (0x0d938 >> ((odd >> 16) & 15)) & 1
        return (0xEC57E80A >> n) & 1
    }
    mutating func word(_ input: UInt32, encrypted: Bool) -> UInt32 {
        var result: UInt32 = 0
        for i in 0..<32 {
            let position = i ^ 24
            let output = filter
            let feedback = (encrypted ? output : 0) ^ ((input >> position) & 1) ^
                (odd & 0x29ce5c) ^ (even & 0x870804)
            let next = even << 1 | UInt32(feedback.nonzeroBitCount & 1)
            even = odd; odd = next
            result |= output << position
        }
        return result
    }
    static func successor(_ value: UInt32) -> UInt32 {
        var x = value.byteSwapped
        for _ in 0..<64 { x = x >> 1 | ((x >> 16) ^ (x >> 18) ^ (x >> 19) ^ (x >> 21)) << 31 }
        return x.byteSwapped
    }
}
