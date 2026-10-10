import Foundation

/// The package name and version from an APK's binary `AndroidManifest.xml`.
public struct AndroidManifest: Equatable, Sendable {
    public let package: String
    public let versionName: String
    public let versionCode: Int

    public init(package: String, versionName: String, versionCode: Int) {
        self.package = package
        self.versionName = versionName
        self.versionCode = versionCode
    }

    public enum Error: Swift.Error, Equatable {
        case notBinaryXML
        case missing(String)
    }

    public static func read(file: URL) throws -> AndroidManifest {
        try read(Data(contentsOf: file))
    }

    /// Reads the attributes of the first tag, which is `manifest`.
    public static func read(_ data: Data) throws -> AndroidManifest {
        let b = [UInt8](data)
        func u16(_ o: Int) throws -> Int {
            guard o >= 0, o + 2 <= b.count else { throw Error.notBinaryXML }
            return Int(b[o]) | Int(b[o + 1]) << 8
        }
        func u32(_ o: Int) throws -> Int {
            guard o >= 0, o + 4 <= b.count else { throw Error.notBinaryXML }
            return Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
        }
        guard try u16(0) == 0x0003 else { throw Error.notBinaryXML }

        // String pool, right after the 8-byte file header.
        let pool = 8
        guard try u16(pool) == 0x0001 else { throw Error.notBinaryXML }
        let count = try u32(pool + 8)
        let utf8 = try u32(pool + 16) & 0x100 != 0
        let stringsStart = pool + (try u32(pool + 20))
        func string(_ index: Int) throws -> String {
            guard index >= 0, index < count else { throw Error.notBinaryXML }
            let o = stringsStart + (try u32(pool + 28 + 4 * index))
            if utf8 {
                guard o + 2 <= b.count else { throw Error.notBinaryXML }
                let length = Int(b[o + 1])
                guard o + 2 + length <= b.count else { throw Error.notBinaryXML }
                return String(decoding: b[(o + 2)..<(o + 2 + length)], as: UTF8.self)
            }
            let length = try u16(o)
            var units: [UInt16] = []
            for i in 0..<length { units.append(UInt16(try u16(o + 2 + 2 * i))) }
            return String(decoding: units, as: UTF16.self)
        }

        // Walk the chunks to the first start tag.
        var chunk = pool + (try u32(pool + 4))
        while try u16(chunk) != 0x0102 {
            let size = try u32(chunk + 4)
            guard size > 0 else { throw Error.notBinaryXML }
            chunk += size
        }
        var values: [String: String] = [:]
        let attributeCount = try u16(chunk + 28)
        for i in 0..<attributeCount {
            let a = chunk + 36 + 20 * i
            let name = try string(try u32(a + 4))
            guard a + 20 <= b.count else { throw Error.notBinaryXML }
            let type = b[a + 15]
            let raw = try u32(a + 8)
            if type == 0x03 || raw != 0xFFFF_FFFF {
                values[name] = try string(raw)
            } else {
                values[name] = String(try u32(a + 16))
            }
        }
        guard let package = values["package"] else { throw Error.missing("package") }
        guard let versionName = values["versionName"] else { throw Error.missing("versionName") }
        guard let code = values["versionCode"].flatMap(Int.init) else { throw Error.missing("versionCode") }
        return AndroidManifest(package: package, versionName: versionName, versionCode: code)
    }
}
