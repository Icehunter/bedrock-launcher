"""Gate diagnostics for Bedrock Android arm64 1.26.62.1.

Import in LLDB, break on mcpelauncher_linker_notifylldb and attach loaded().
The default mode sets breakpoints. FIX_NORMALIZED_RGBA16 checks the game version
and changes the texture format table in process memory. Game files stay unchanged.
"""
import lldb
import struct

BASE = 0
FIX_NORMALIZED_RGBA16 = False
TRACE_TEXTURE_FORMATS = False
TEXTURE_POINTS = {0x11DA3ADC: 'w2', 0x11DA3C80: 'w24'}
COPY_TRACE_COUNT = 0
POINTS = {
    0x11DA1C4C: 'normalized texture format table',
    0x10005870: 'device tier lookup input',
    0xB0BF274: 'platform classification',
    0xB0BF364: 'device tier parse input',
    0x118193DC: 'GraphicsFeatureQuery deferred hardware result',
    0xB0BF2F8: 'RayTracingHardwareOptions cached deferred result',
    0xB0BFAEC: 'RayTracingOptions content capability result',
    0xB2EF418: 'Settings deferred mode eligibility result',
}


def reg(frame, name):
    return frame.FindRegister(name).GetValueAsUnsigned()


def vulkan_copy(frame, bp_loc, internal_dict):
    """Log small copies that match validation hazards without changing them."""
    global COPY_TRACE_COUNT
    if COPY_TRACE_COUNT >= 24:
        return False
    process = frame.GetThread().GetProcess()
    count = reg(frame, 'w5')
    if count < 1 or count > 64:
        return False
    err = lldb.SBError()
    raw = process.ReadMemory(reg(frame, 'x6'), count * 68, err)
    if err.Fail() or len(raw) != count * 68:
        return False
    regions = [struct.unpack_from('<17I', raw, i * 68) for i in range(count)]
    if not any(r[14:16] in ((1, 1), (23, 15)) for r in regions):
        return False
    COPY_TRACE_COUNT += 1
    print('VV_COPY source=0x%x destination=0x%x src_layout=%d dst_layout=%d regions=%r' % (
        reg(frame, 'x1'), reg(frame, 'x3'), reg(frame, 'w2'), reg(frame, 'w4'), regions), flush=True)
    thread = frame.GetThread()
    for i in range(min(thread.GetNumFrames(), 16)):
        caller = thread.GetFrameAtIndex(i)
        print('VV_COPY_FRAME %d pc=0x%x %s %s' % (
            i, caller.GetPC(), caller.GetModule().GetFileSpec().GetFilename(),
            caller.GetFunctionName() or '?'), flush=True)
    return False


def texture_format(frame, bp_loc, internal_dict):
    process = frame.GetThread().GetProcess()
    err = lldb.SBError()
    raw = process.ReadMemory(reg(frame, 'x20'), 0x30, err)
    if err.Fail() or len(raw) != 0x30:
        print('VV_TEXTURE read failed: %s' % err, flush=True)
        return False
    requested, actual = raw[0x2d], raw[0x2e]
    # Log normalized and integer texture formats.
    if requested not in (53, 55, 71, 73) and actual not in (53, 55, 71, 73):
        return False
    offset = frame.GetPC() - BASE
    u32 = lambda at: struct.unpack_from('<I', raw, at)[0]
    print('VV_TEXTURE pc=0x%x id=%d requested=%d actual=%d internal=0x%x '
          'transfer=0x%x type=0x%x width=%d height=%d table_field=0x%x' % (
              offset, u32(0), requested, actual, reg(frame, TEXTURE_POINTS[offset]),
              u32(0xc), u32(0x10), u32(0x1c), u32(0x20), reg(frame, 'x8') - BASE),
          flush=True)
    return False


def gate(frame, bp_loc, internal_dict):
    process = frame.GetThread().GetProcess()
    offset = frame.GetPC() - BASE
    print('VV_GATE offset=0x%x label=%s w0=%d w23=%d x19=0x%x x20=0x%x' % (
        offset, POINTS.get(offset, '?'), reg(frame, 'w0'), reg(frame, 'w23'),
        reg(frame, 'x19'), reg(frame, 'x20')), flush=True)
    if offset == 0x11DA1C4C and FIX_NORMALIZED_RGBA16:
        # GLES initialization replaces normalized RG16/RGBA16 with UINT slots.
        # Restore the internal and transfer formats. Keep integer slots,
        # type=UNSIGNED_SHORT and the probe's support flags.
        err = lldb.SBError()
        rows = [(0x140429AC, 0x823A, 0x8228, 0x822C, 0x8227),
                (0x14042B14, 0x8D76, 0x8D99, 0x805B, 0x1908)]
        snapshots = []
        for address, old_internal, old_format, new_internal, new_format in rows:
            raw = process.ReadMemory(BASE + address, 20, err)
            if err.Fail() or len(raw) != 20:
                print('VV_FORMAT refused: cannot read table', flush=True)
                return False
            values = struct.unpack('<5I', raw)
            if values[0] != old_internal or values[2] != old_format or values[3] != 0x1403:
                print('VV_FORMAT refused: unexpected row 0x%x %r' % (address, values), flush=True)
                return False
            snapshots.append((address, values, new_internal, new_format))
        for address, before, new_internal, new_format in snapshots:
            for field, value in [(0, new_internal), (8, new_format)]:
                count = process.WriteMemory(BASE + address + field, struct.pack('<I', value), err)
                if err.Fail() or count != 4:
                    print('VV_FORMAT write failed: %s' % err, flush=True)
                    return True
            raw = process.ReadMemory(BASE + address, 20, err)
            if err.Fail() or len(raw) != 20:
                print('VV_FORMAT cannot verify write: %s' % err, flush=True)
                return True
            after = struct.unpack('<5I', raw)
            expected = list(before)
            expected[0], expected[2] = new_internal, new_format
            if list(after) != expected:
                print('VV_FORMAT verification mismatch: %r' % (after,), flush=True)
                return True
            print('VV_FORMAT row=0x%x before=%r after=%r' % (address, before, after), flush=True)
    if offset == 0x10005870:
        err = lldb.SBError()
        address = reg(frame, 'x19')
        tag = process.ReadUnsignedFromMemory(address, 1, err)
        pointer = process.ReadUnsignedFromMemory(address + 16, 8, err) if tag & 1 else address + 1
        value = process.ReadCStringFromMemory(pointer, 512, err)
        print('VV_GATE device_tier_lookup_input=%r error=%s' % (value, err), flush=True)
    if offset == 0xB0BF364:
        err = lldb.SBError()
        value = process.ReadCStringFromMemory(reg(frame, 'x0'), 256, err)
        print('VV_GATE device_tier_string=%r error=%s' % (value, err), flush=True)
    if offset == 0x118193DC:
        err = lldb.SBError()
        caps = BASE + 0x14248EA8
        fields = [('renderer', caps, 4), ('gles_version', BASE + 0x142490D0, 8),
                  ('caps', caps + 0x238, 8), ('max_compute_invocations', caps + 0x15A8, 4)]
        for name, address, size in fields:
            value = process.ReadUnsignedFromMemory(address, size, err)
            print('VV_GATE %s=%s error=%s' % (name, hex(value), err), flush=True)
    return False


def loaded(frame, bp_loc, internal_dict):
    global BASE
    process = frame.GetThread().GetProcess()
    err = lldb.SBError()
    filename = process.ReadCStringFromMemory(reg(frame, 'x0'), 2048, err)
    if not filename.endswith('/1.26.62.1/lib/arm64-v8a/libminecraftpe.so'):
        return False
    candidate = reg(frame, 'x1')
    # Check game instructions before setting breakpoints at version-specific offsets.
    for offset, expected in [(0x11DA1C4C, 0x9460C9A1),
                             (0x118193DC, 0xA8C17BFD), (0xB0BF2F8, 0x39006677),
                             (0xB0BFAEC, 0x3900EA6A), (0xB2EF418, 0xF94016C8)]:
        actual = process.ReadUnsignedFromMemory(candidate + offset, 4, err)
        if err.Fail() or actual != expected:
            print('VV_GATE refused: instruction mismatch offset=0x%x actual=0x%x' % (offset, actual), flush=True)
            return False
    BASE = candidate
    target = process.GetTarget()
    if TRACE_TEXTURE_FORMATS:
        for offset, expected in [(0x11DA3ADC, 0x6B0902FF), (0x11DA3C80, 0x946316F0)]:
            actual = process.ReadUnsignedFromMemory(BASE + offset, 4, err)
            if err.Fail() or actual != expected:
                print('VV_TEXTURE refused: instruction mismatch at 0x%x' % offset, flush=True)
                return False
        for offset in TEXTURE_POINTS:
            bp = target.BreakpointCreateByAddress(BASE + offset)
            bp.SetScriptCallbackFunction(__name__ + '.texture_format')
    for offset in POINTS:
        bp = target.BreakpointCreateByAddress(BASE + offset)
        bp.SetScriptCallbackFunction(__name__ + '.gate')
    print('VV_GATE armed base=0x%x' % BASE, flush=True)
    return False
