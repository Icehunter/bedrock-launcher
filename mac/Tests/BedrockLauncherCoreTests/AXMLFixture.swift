import Foundation

/// Builds small binary AndroidManifest.xml files, laid out the way Android
/// tools write them: a string pool, a namespace chunk, then a `manifest` tag.
enum AXMLFixture {
    static func make(package: String, versionName: String, versionCode: Int?, utf8: Bool) -> Data {
        var strings = ["manifest", "package", "versionName", "versionCode", "android", "http://schemas.android.com/apk/res/android", package, versionName]
        if versionCode == nil { strings[3] = "installLocation" }

        var pool = Data()
        var offsets: [UInt32] = []
        for s in strings {
            offsets.append(UInt32(pool.count))
            if utf8 {
                let bytes = Array(s.utf8)
                pool.append(UInt8(s.count)); pool.append(UInt8(bytes.count))
                pool.append(contentsOf: bytes); pool.append(0)
            } else {
                let units = Array(s.utf16)
                pool.append(u16(UInt16(units.count)))
                for u in units { pool.append(u16(u)) }
                pool.append(u16(0))
            }
        }
        while pool.count % 4 != 0 { pool.append(0) }
        let poolHeader = 28
        let stringsStart = poolHeader + 4 * strings.count
        var poolChunk = Data()
        poolChunk.append(u16(0x0001)); poolChunk.append(u16(UInt16(poolHeader)))
        poolChunk.append(u32(UInt32(stringsStart + pool.count)))
        poolChunk.append(u32(UInt32(strings.count))); poolChunk.append(u32(0))
        poolChunk.append(u32(utf8 ? 0x100 : 0)); poolChunk.append(u32(UInt32(stringsStart))); poolChunk.append(u32(0))
        for o in offsets { poolChunk.append(u32(o)) }
        poolChunk.append(pool)

        var ns = Data()
        ns.append(u16(0x0100)); ns.append(u16(16)); ns.append(u32(24))
        ns.append(u32(1)); ns.append(u32(0xFFFF_FFFF)); ns.append(u32(4)); ns.append(u32(5))

        func attr(name: Int, string: Int) -> Data {
            var a = Data()
            a.append(u32(5)); a.append(u32(UInt32(name))); a.append(u32(UInt32(string)))
            a.append(u16(8)); a.append(0); a.append(0x03); a.append(u32(UInt32(string)))
            return a
        }
        func attr(name: Int, int value: Int) -> Data {
            var a = Data()
            a.append(u32(5)); a.append(u32(UInt32(name))); a.append(u32(0xFFFF_FFFF))
            a.append(u16(8)); a.append(0); a.append(0x10); a.append(u32(UInt32(value)))
            return a
        }
        let attrs = [attr(name: 1, string: 6), attr(name: 2, string: 7), attr(name: 3, int: versionCode ?? 2)]
        var element = Data()
        element.append(u16(0x0102)); element.append(u16(16))
        element.append(u32(UInt32(36 + 20 * attrs.count)))
        element.append(u32(1)); element.append(u32(0xFFFF_FFFF))
        element.append(u32(0xFFFF_FFFF)); element.append(u32(0))
        element.append(u16(20)); element.append(u16(20)); element.append(u16(UInt16(attrs.count)))
        element.append(u16(0)); element.append(u16(0)); element.append(u16(0))
        for a in attrs { element.append(a) }

        var file = Data()
        file.append(u16(0x0003)); file.append(u16(8))
        file.append(u32(UInt32(8 + poolChunk.count + ns.count + element.count)))
        file.append(poolChunk); file.append(ns); file.append(element)
        return file
    }

    static func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
