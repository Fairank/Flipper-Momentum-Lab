import Foundation

/// Errors from parsing or merging MIFARE Classic key dictionaries; `errorDescription` is the
/// user-facing Chinese message. Line numbers are 1-based and count every line of the input,
/// including blank and comment lines, so they match what a text editor shows.
public enum NFCKeyDictionaryError: Error, Equatable, Sendable {
    /// The UTF-8 byte count of the input exceeds `NFCKeyDictionary.maxBytes`.
    case inputTooLarge(byteCount: Int, limit: Int)
    /// No key lines at all: the text is empty or holds only blank lines and comments.
    case emptyDictionary
    /// A key line contains a character that is neither a hex digit nor an allowed separator.
    /// `character` is the character itself when visible, otherwise `U+XXXX`.
    case invalidCharacter(line: Int, character: String)
    /// A key line has a number of hex digits other than 12.
    case invalidKeyLength(line: Int, digitCount: Int)
    /// A key line has 12 hex digits, but its separators are misplaced, repeated, or mixed.
    case invalidSeparators(line: Int)
    /// More than `NFCKeyDictionary.maxKeys` distinct keys were supplied.
    case tooManyKeys(limit: Int)
}

extension NFCKeyDictionaryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .inputTooLarge(byteCount, limit):
            return "密钥字典为 \(Self.describeBytes(byteCount))，超过上限 \(Self.describeBytes(limit))。"
        case .emptyDictionary:
            return "密钥字典中没有密钥：内容为空，或只有空行和注释。"
        case let .invalidCharacter(line, character):
            if character == "#" {
                return "第 \(line) 行在密钥之后出现“#”：注释必须单独成行，以 # 开头。"
            }
            return "第 \(line) 行含有无效字符“\(character)”：密钥只能由十六进制数字组成，字节之间可用空格或冒号分隔。"
        case let .invalidKeyLength(line, digitCount):
            let expected = NFCKeyDictionary.keyDigitCount
            if digitCount == 0 {
                return "第 \(line) 行没有十六进制数字。"
            }
            if digitCount > expected, digitCount % expected == 0 {
                return "第 \(line) 行有 \(digitCount) 个十六进制数字，看起来包含多个密钥；每行只能写一个 \(expected) 位密钥。"
            }
            return "第 \(line) 行的密钥有 \(digitCount) 个十六进制数字，MIFARE Classic 密钥应为 \(expected) 个（6 字节）。"
        case let .invalidSeparators(line):
            return "第 \(line) 行的分隔符不正确：空格或冒号只能出现在每两位十六进制数字之间，且整行只能使用同一种分隔符。"
        case let .tooManyKeys(limit):
            return "不同密钥的数量超过上限 \(limit) 个。"
        }
    }

    private static func describeBytes(_ count: Int) -> String {
        if count >= 1024 * 1024, count % (1024 * 1024) == 0 { return "\(count / (1024 * 1024)) MiB" }
        if count >= 1024, count % 1024 == 0 { return "\(count / 1024) KiB" }
        return "\(count) 字节"
    }
}

/// Offline manager for MIFARE Classic key dictionaries in the plain-text format shared by the
/// firmware (`mf_classic_dict.nfc`, `mf_classic_dict_user.nfc`), Proxmark `.dic` and MCT `.keys`
/// files: one 48-bit key as 12 hex digits per line, `#` comment lines, blank lines.
///
/// Parsing canonicalizes keys to uppercase, keeps first-seen order, drops duplicates, and rejects
/// every malformed non-comment line with its line number instead of skipping it. The firmware's
/// `keys_dict` reader truncates each line to 12 characters and compares keys as text, so the
/// canonical output here (uppercase, LF, no comments, final newline) is the form it writes itself.
///
/// This type only reformats and merges candidate keys the user already has. It never talks to a
/// reader or a card, does not recover keys, and does not search the key space.
public struct NFCKeyDictionary: Equatable, Sendable {
    /// Maximum UTF-8 size of one input text (2 MiB).
    public static let maxBytes = 2 * 1024 * 1024
    /// Maximum number of distinct keys in a parsed or merged dictionary. At 13 bytes per output
    /// line this keeps `text` at or under 1.3 MB, so every merged result can be parsed again.
    public static let maxKeys = 100_000
    /// Hex digits per key: 6 bytes, 48 bits.
    public static let keyDigitCount = 12

    /// Canonical keys: 12 uppercase hex digits each, in first-seen order, without duplicates.
    /// Never empty; an input or merge without keys throws `NFCKeyDictionaryError.emptyDictionary`.
    public let keys: [String]

    /// Parses dictionary text. An optional UTF-8 BOM may precede the first line; LF, CRLF and a
    /// lone CR all end a line. Leading and trailing spaces or tabs on a line are ignored. A line
    /// whose first remaining character is `#` is a comment. Every other non-blank line must be one
    /// key: `FFFFFFFFFFFF`, `FF FF FF FF FF FF` or `FF:FF:FF:FF:FF:FF`, in either letter case.
    public init(text: String) throws {
        let byteCount = text.utf8.count
        guard byteCount <= Self.maxBytes else {
            throw NFCKeyDictionaryError.inputTooLarge(byteCount: byteCount, limit: Self.maxBytes)
        }
        let bytes = Array(text.utf8)
        var keys: [String] = []
        var seen: Set<String> = []
        var lineNumber = 1
        var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while index < bytes.count {
            var end = index
            while end < bytes.count, bytes[end] != 0x0A, bytes[end] != 0x0D { end += 1 }
            if let key = try Self.parseKeyLine(bytes, index..<end, line: lineNumber), seen.insert(key).inserted {
                guard keys.count < Self.maxKeys else {
                    throw NFCKeyDictionaryError.tooManyKeys(limit: Self.maxKeys)
                }
                keys.append(key)
            }
            if end < bytes.count {
                if bytes[end] == 0x0D, end + 1 < bytes.count, bytes[end + 1] == 0x0A { end += 1 }
                end += 1
            }
            index = end
            lineNumber += 1
        }
        guard !keys.isEmpty else { throw NFCKeyDictionaryError.emptyDictionary }
        self.keys = keys
    }

    /// Only for `merge`, whose inputs already hold canonical keys.
    private init(keys: [String]) {
        self.keys = keys
    }

    /// Concatenates the dictionaries in argument order, keeping the first occurrence of each key.
    /// The result is bounded by `maxKeys` like a parsed dictionary; an empty result is an error.
    public static func merge(_ dictionaries: [NFCKeyDictionary]) throws -> NFCKeyDictionary {
        var keys: [String] = []
        keys.reserveCapacity(min(dictionaries.reduce(0) { $0 + $1.keys.count }, maxKeys))
        var seen: Set<String> = []
        for dictionary in dictionaries {
            for key in dictionary.keys {
                guard seen.insert(key).inserted else { continue }
                guard keys.count < maxKeys else { throw NFCKeyDictionaryError.tooManyKeys(limit: maxKeys) }
                keys.append(key)
            }
        }
        guard !keys.isEmpty else { throw NFCKeyDictionaryError.emptyDictionary }
        return NFCKeyDictionary(keys: keys)
    }

    /// One key per line, LF separated, with a final newline and no comments.
    public var text: String {
        keys.joined(separator: "\n") + "\n"
    }
}

// MARK: - Line parsing

extension NFCKeyDictionary {
    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")
    private static let colon = UInt8(ascii: ":")
    private static let hash = UInt8(ascii: "#")

    /// The canonical key on a key line, or nil for a blank or comment line.
    private static func parseKeyLine(_ bytes: [UInt8], _ range: Range<Int>, line: Int) throws -> String? {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, bytes[start] == space || bytes[start] == tab { start += 1 }
        while end > start, bytes[end - 1] == space || bytes[end - 1] == tab { end -= 1 }
        guard start < end, bytes[start] != hash else { return nil }

        var digitCount = 0
        var hasSeparator = false
        for offset in start..<end {
            let byte = bytes[offset]
            if isHexDigit(byte) {
                digitCount += 1
            } else if byte == space || byte == colon {
                hasSeparator = true
            } else {
                throw NFCKeyDictionaryError.invalidCharacter(
                    line: line, character: describe(bytes[offset..<end].prefix(4)))
            }
        }
        guard digitCount == keyDigitCount else {
            throw NFCKeyDictionaryError.invalidKeyLength(line: line, digitCount: digitCount)
        }

        var canonical: [UInt8] = []
        canonical.reserveCapacity(keyDigitCount)
        if hasSeparator {
            // Exactly six byte pairs joined by one separator each: "HH?HH?HH?HH?HH?HH".
            let width = keyDigitCount + keyDigitCount / 2 - 1
            guard end - start == width else { throw NFCKeyDictionaryError.invalidSeparators(line: line) }
            let separator = bytes[start + 2]
            guard separator == space || separator == colon else {
                throw NFCKeyDictionaryError.invalidSeparators(line: line)
            }
            for offset in 0..<width {
                let byte = bytes[start + offset]
                if offset % 3 == 2 {
                    guard byte == separator else { throw NFCKeyDictionaryError.invalidSeparators(line: line) }
                } else {
                    guard isHexDigit(byte) else { throw NFCKeyDictionaryError.invalidSeparators(line: line) }
                    canonical.append(uppercased(byte))
                }
            }
        } else {
            for offset in start..<end { canonical.append(uppercased(bytes[offset])) }
        }
        return String(decoding: canonical, as: UTF8.self)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "A")...UInt8(ascii: "F"),
             UInt8(ascii: "a")...UInt8(ascii: "f"):
            return true
        default:
            return false
        }
    }

    private static func uppercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte) ? byte - 0x20 : byte
    }

    /// The first scalar of `rest` for an error message: shown as itself when visible, otherwise
    /// as `U+XXXX` so that control characters, non-ASCII spaces and a stray BOM do not vanish
    /// from the message. `rest` starts at a scalar boundary because everything before it on the
    /// line was single-byte ASCII; four bytes always cover one complete UTF-8 scalar.
    private static func describe(_ rest: ArraySlice<UInt8>) -> String {
        guard let scalar = String(decoding: rest, as: UTF8.self).unicodeScalars.first else { return "?" }
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned,
             .spaceSeparator, .lineSeparator, .paragraphSeparator:
            let hex = String(scalar.value, radix: 16, uppercase: true)
            return "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
        default:
            return String(Character(scalar))
        }
    }
}
