# Vibrant Visuals on macOS

## Status

Bedrock 1.26.62.1 renders water and Snell's window correctly with the GL ABI
adapter on Apple M5 Pro. The same build passes a visual check in Fancy mode.
The tested path is ANGLE Vulkan, MoltenVK, Metal.

These runs use two diagnostic settings in addition to the client changes:

- A separate game asset view assigns Apple M5 Pro to device tier 4.
- An LLDB script keeps RG16 and RGBA16 texture format entries normalized.

A normal launch without these settings is not verified. The ABI fix is suitable
for the client, but automatic VV support still needs the tier and format handling.

## GL argument layout

Android ARM64 places each integer stack argument in an eight-byte slot.
Darwin ARM64 packs 32-bit stack arguments into four-byte slots. Passing a host
GL pointer straight to the game therefore breaks calls with several integer
arguments on the stack.

The game's glCopyImageSubDataEXT caller stores arguments 9 through 15 at offsets
0, 8, 16, 24, 32, 40 and 48. Darwin reads them at 0, 4, 8, 12, 16, 20 and 24.
The wrong layout makes width read dstY and depth read dstZ. Cubemap copies reach
ANGLE with zero width and height. glTexSubImage3D receives a GL type enum where
its data pointer belongs.

The client adapter reads Android slots and calls the native function with its
Darwin signature. It covers 11 names across these four GL function families:

- CopyImageSubData: core, EXT, OES.
- BlitFramebuffer: core, ANGLE, EXT, NV.
- TexSubImage3D: core, OES.
- CompressedTexSubImage3D: core, OES.

GLAD and native GL patch helpers use the native resolver. Android ELF imports
and the game's eglGetProcAddress use the adapter. Other hosts pass through.

The assembly caller test checks all 11 names, signed integer values, unused
upper bits and a full 64-bit pointer. All 11 fail with raw native pointers and
pass through the adapter. Live tracing shows 16x16x1 cubemap copies and valid
upload pointers with the adapter.

Native macOS render tests do not cover this boundary. They use Darwin callers
on both sides of the call.

## Device tier and texture formats

The game's default device tier is 3. Its VV gate requires a tier above 3.
`tools/gltrace/create-tier-overlay.py` creates a separate asset view with a GPU
rule. It leaves the original install untouched.

The game's GLES setup maps normalized RG16 and RGBA16 rows to integer formats.
Float shader outputs then target integer attachments. The opt-in
`FIX_NORMALIZED_RGBA16` setting in `tools/gltrace/vv_gate_lldb.py` restores the
normalized rows in process memory. It preserves the unsigned-short transfer
type and leaves true integer rows alone. The script checks the expected code
before changing memory and is specific to Bedrock 1.26.62.1.

The format correction removes the shader-output format warning. On its own,
it does not fix the visible water and texture errors. The visual pass uses
both the format correction and the ABI adapter.

## Driver findings

The MoltenVK fork's float/integer format swap changes the pipeline format while
the attachment stays integer. It is not a general solution for normalized
G-buffer data. A numeric float-to-integer conversion would lose values between
zero and one. The ABI change does not alter MoltenVK or SPIRV-Cross.

The game's 131 GL names classified as GLES 3.1 or earlier core functions all
resolve through bundled ANGLE. Missing optional desktop and vendor names do
not establish a missing required call.

The native render harness covers framebuffer fetch, integer attachments,
texture sampling, image copies and first-use compute image bindings. These
checks pass on the tested stack. Small-copy synchronization warnings remain
under Vulkan validation; their effect on game rendering is not established.

## Tools

`tools/gltrace/README.md` describes the GL trace build and runner.
`tools/render-tests/build.sh` builds the native GL harness against `out/angle`.
Run the harness with an absolute Vulkan ICD JSON path and an optional test-name
filter. The client repository contains the Android-layout assembly caller test
and the optional `CLIENT_BUILD_GL_ANDROID_ABI_TESTS` CMake target.
