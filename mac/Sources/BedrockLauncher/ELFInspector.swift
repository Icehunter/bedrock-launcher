import Foundation

struct ELFReport {
    var loadSegments: Int
    var memorySpan: UInt64
    var needed: [String]
}

enum ELFError: LocalizedError {
    case notELF64LE
    case notAArch64(UInt16)
    case truncated
    case noDynamic

    var errorDescription: String? {
        switch self {
        case .notELF64LE: return "Not a 64-bit little-endian ELF file."
        case .notAArch64(let m): return "ELF machine \(m) is not aarch64 (183)."
        case .truncated: return "ELF headers point outside the file."
        case .noDynamic: return "No PT_DYNAMIC segment."
        }
    }
}

private extension Data {
    func read<T>(_ offset: Int) -> T {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}

/// Milestone 1: parse the ELF headers and list what the loader must provide.
/// Next milestones: mmap the PT_LOAD segments, apply relocations, resolve the
/// DT_NEEDED libraries (libc, libm, libdl, liblog, libandroid, libEGL, libGLESv3...)
/// against shims, then call JNI_OnLoad.
enum ELFInspector {
    static func inspect(_ url: URL) throws -> ELFReport {
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        guard d.count > 64, d[0] == 0x7f, d[1] == 0x45, d[2] == 0x4c, d[3] == 0x46,
              d[4] == 2, d[5] == 1 else { throw ELFError.notELF64LE }

        let machine: UInt16 = d.read(18)
        guard machine == 183 else { throw ELFError.notAArch64(machine) }

        let phoff = Int(d.read(32) as UInt64)
        let phentsize = Int(d.read(54) as UInt16)
        let phnum = Int(d.read(56) as UInt16)
        guard phoff + phentsize * phnum <= d.count else { throw ELFError.truncated }

        struct Seg { var off: UInt64; var vaddr: UInt64; var filesz: UInt64; var memsz: UInt64 }
        var loads: [Seg] = []
        var dynOff = 0
        var dynSize = 0

        for i in 0..<phnum {
            let b = phoff + i * phentsize
            let type: UInt32 = d.read(b)
            let off: UInt64 = d.read(b + 8)
            let vaddr: UInt64 = d.read(b + 16)
            let filesz: UInt64 = d.read(b + 32)
            let memsz: UInt64 = d.read(b + 40)
            if type == 1 {
                loads.append(Seg(off: off, vaddr: vaddr, filesz: filesz, memsz: memsz))
            } else if type == 2 {
                dynOff = Int(off)
                dynSize = Int(filesz)
            }
        }
        guard dynSize > 0 else { throw ELFError.noDynamic }

        func fileOffset(_ vaddr: UInt64) -> Int? {
            for s in loads where vaddr >= s.vaddr && vaddr < s.vaddr + s.filesz {
                return Int(s.off + vaddr - s.vaddr)
            }
            return nil
        }

        var neededOffsets: [UInt64] = []
        var strtab: UInt64 = 0
        var p = dynOff
        while p + 16 <= dynOff + dynSize && p + 16 <= d.count {
            let tag: Int64 = d.read(p)
            let val: UInt64 = d.read(p + 8)
            if tag == 0 { break }
            if tag == 1 { neededOffsets.append(val) }
            if tag == 5 { strtab = val }
            p += 16
        }
        guard let strBase = fileOffset(strtab) else { throw ELFError.truncated }

        var names: [String] = []
        for o in neededOffsets {
            var q = strBase + Int(o)
            var bytes: [UInt8] = []
            while q < d.count, d[q] != 0 { bytes.append(d[q]); q += 1 }
            names.append(String(decoding: bytes, as: UTF8.self))
        }

        let lo = loads.map { $0.vaddr }.min() ?? 0
        let hi = loads.map { $0.vaddr + $0.memsz }.max() ?? 0
        return ELFReport(loadSegments: loads.count, memorySpan: hi - lo, needed: names)
    }
}
