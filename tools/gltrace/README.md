Build from the repository root for the bundled client's architecture:

```sh
clang -std=c11 -dynamiclib -Wall -Wextra -Werror -I deps/angle/include \
  tools/gltrace/gltrace.c -o tools/gltrace/libgltrace.dylib
codesign --force --sign - tools/gltrace/libgltrace.dylib
```

Run with the same arguments as `scripts/run-bundle.sh`:

```sh
GLTRACE_FILE=/tmp/gltrace.log bash tools/gltrace/run.sh \
  path/to/Client.app/Contents path/to/game path/to/data [client args...]
```

The runner sets `DYLD_INSERT_LIBRARIES` before starting the native client.
macOS `/bin/bash` removes this variable when it starts. The startup log line
confirms the library loaded, even if no GL calls occur.

The Android ELF loader stores GL pointers from `fake_egl::eglGetProcAddress`
and GLFW. Exported GL symbols do not catch calls through these pointers.
The tracer wraps native `dlsym` and GLFW's `eglGetProcAddress` to log calls
through known GL pointers. Unknown and missing names pass through unchanged.
The tracer supports one ANGLE library per client process.

Verify injection and pointer forwarding without running Minecraft:

```sh
bash tools/gltrace/smoke-test.sh
```

The smoke test builds a fake GL library and client. It checks symbol lookup,
EGL lookup, unknown and missing names, and the runner. Outputs remain in the
temporary directory printed by the test.

The tracer logs 3D/array allocation and updates, compressed data, 2D/3D
immutable storage, framebuffer layer attachments, and memory barriers.
CopyImageSubData EXT/OES and CopyTexSubImage 2D/3D write BEGIN/END records
with a shared copy ID, full arguments, dimensions and caller PC. CopyTex
destinations use the current bindings. Their IDs come from earlier ActiveTexture
and BindTexture records. The wrappers insert no glGetError, flush, barrier or
other synchronization calls. Extension copy signatures use GLES2/gl2ext.h.
