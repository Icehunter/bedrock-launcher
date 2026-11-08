#!/usr/bin/env bash
# Check dyld lookup and the launch environment without a game.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gltrace-smoke.XXXXXX")"
# Outputs remain in this directory for inspection.
mkdir -p "$TMP/Contents/MacOS" "$TMP/game" "$TMP/data"
cat > "$TMP/provider.c" <<'C'
#include <string.h>
const unsigned char *glGetString(unsigned int name) { (void)name; return (const unsigned char *)"fake ANGLE"; }
const unsigned char *glGetStringi(unsigned int name, unsigned int index) { return name == 0x1f03 && index == 2 ? (const unsigned char *)"GL_FAKE_indexed" : 0; }
void glGetIntegerv(unsigned int name, int *out) { if (out) *out = (int)name + 7; }
void glGetInternalformativ(unsigned int target, unsigned int format, unsigned int pname, int size, int *out) {
    (void)target; (void)format; (void)pname;
    for (int i = 0; out && i < size; ++i) out[i] = 100 + i;
}
int untouched(void) { return 17; }
void *eglGetProcAddress(const char *name) { return strcmp(name, "glGetString") == 0 ? (void *)glGetString : 0; }
C
cat > "$TMP/probe.c" <<'C'
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    void *h = dlopen(getenv("GLTRACE_SMOKE_PROVIDER"), RTLD_NOW | RTLD_LOCAL);
    if (!h) return 1;
    const unsigned char *(*get)(unsigned int) = dlsym(h, "glGetString");
    void *(*resolve)(const char *) = dlsym(h, "eglGetProcAddress");
    if (!get || !resolve) return 2;
    const unsigned char *(*via_proc)(unsigned int) = resolve("glGetString");
    const unsigned char *(*indexed)(unsigned int, unsigned int) = dlsym(h, "glGetStringi");
    void (*integer)(unsigned int, int *) = dlsym(h, "glGetIntegerv");
    void (*internal)(unsigned int, unsigned int, unsigned int, int, int *) = dlsym(h, "glGetInternalformativ");
    if (!indexed || !integer || !internal || strcmp((const char *)indexed(0x1f03, 2), "GL_FAKE_indexed") || indexed(0x1f03, 9)) return 4;
    int value = 0;
    integer(0x8cdf, &value);
    if (value != 0x8ce6) return 5;
    int values[3] = {-1, -1, -999};
    internal(0x8d41, 0x8058, 0x80a9, 2, values);
    if (values[0] != 100 || values[1] != 101 || values[2] != -999) return 6;
    internal(0x8d41, 0x8058, 0x80a9, 0, NULL);
    int (*other)(void) = dlsym(h, "untouched");
    if (!get || !resolve || !via_proc || !other) return 2;
    if (strcmp((const char *)get(0x1f02), "fake ANGLE") ||
        strcmp((const char *)via_proc(0x1f00), "fake ANGLE") || other() != 17 ||
        resolve("glMissing") || dlsym(h, "glMissing")) return 3;
    puts("forwarding ok");
    return 0;
}
C
clang -dynamiclib -Wall -Wextra -Werror "$TMP/provider.c" -o "$TMP/provider.dylib"
clang -Wall -Wextra -Werror "$TMP/probe.c" -o "$TMP/Contents/MacOS/mcpelauncher-client"
clang -std=c11 -dynamiclib -Wall -Wextra -Werror -I "$ROOT/deps/angle/include" \
  "$ROOT/tools/gltrace/gltrace.c" -o "$TMP/libgltrace.dylib"
GLTRACE_SMOKE_PROVIDER="$TMP/provider.dylib" GLTRACE_FILE="$TMP/direct.log" \
  DYLD_INSERT_LIBRARIES="$TMP/libgltrace.dylib" "$TMP/Contents/MacOS/mcpelauncher-client"
rg -q 'loaded; waiting.*pid=[0-9]+ executable=' "$TMP/direct.log"
rg -q 'bind glGetStringi.*image=.*provider.dylib' "$TMP/direct.log"
rg -q 'glGetStringi.*GL_FAKE_indexed caller=0x' "$TMP/direct.log"
rg -q 'glGetIntegerv.*caller=0x' "$TMP/direct.log"
rg -q '\[1\] = 101' "$TMP/direct.log"
if rg -q '\[2\] = -999' "$TMP/direct.log"; then exit 7; fi
rg -q 'glGetString\(VERSION\) -> fake ANGLE' "$TMP/direct.log"
rg -q 'glGetString\(VENDOR\) -> fake ANGLE' "$TMP/direct.log"
# The runner loads the dylib beside its script.
cp "$ROOT/tools/gltrace/run.sh" "$TMP/run.sh"
GLTRACE_SMOKE_PROVIDER="$TMP/provider.dylib" GLTRACE_FILE="$TMP/runner.log" \
  bash "$TMP/run.sh" "$TMP/Contents" "$TMP/game" "$TMP/data"
rg -q 'glGetString\(VERSION\) -> fake ANGLE' "$TMP/runner.log"
rg -q 'glGetString\(VENDOR\) -> fake ANGLE' "$TMP/runner.log"
printf 'PASS: direct lookup, EGL resolver, unknown/missing symbols, and trace runner; artifacts: %s\n' "$TMP"
