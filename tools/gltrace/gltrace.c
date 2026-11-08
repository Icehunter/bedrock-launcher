// Logs Minecraft Bedrock GL capability queries and rendering calls.
//
// Load directly into the client. System shells remove incoming DYLD variables.
// Wrap dlsym and eglGetProcAddress to catch calls through ANGLE GL pointers.
// Log goes to $GLTRACE_FILE (default: /tmp/gltrace.log).

#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <GLES3/gl31.h>
#define GL_GLEXT_PROTOTYPES 1
#include <GLES2/gl2ext.h>

static FILE *gLog = NULL;
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
static long gSeq = 0;

static void lograw(const char *fmt, ...)
{
    va_list ap;
    pthread_mutex_lock(&gLogLock);
    if (!gLog) {
        const char *p = getenv("GLTRACE_FILE");
        gLog = (p && *p) ? fopen(p, "a") : fopen("/tmp/gltrace.log", "a");
        if (!gLog) gLog = stderr;
        fprintf(gLog, "=== gltrace: interposer active ===\n");
    }
    long seq = ++gSeq;
    va_start(ap, fmt);
    fprintf(gLog, "#%05ld ", seq);
    vfprintf(gLog, fmt, ap);
    va_end(ap);
    fflush(gLog);
    pthread_mutex_unlock(&gLogLock);
}

#define LOG(...) lograw(__VA_ARGS__)

// Save each pointer returned by the application's resolver, including extensions.
struct TraceEntry {
    const char *name;
    void *wrapper;
    _Atomic(void *) real;
};
#define ENTRY(name) {#name, (void *)name, NULL}
static struct TraceEntry entries[] = {
    ENTRY(glGetString),
    ENTRY(glGetStringi),
    ENTRY(glGetInternalformativ),
    ENTRY(glGetIntegerv),
    ENTRY(glGetFloatv),
    ENTRY(glGetError),
    ENTRY(glGetShaderPrecisionFormat),
    ENTRY(glCreateShader),
    ENTRY(glShaderSource),
    ENTRY(glCompileShader),
    ENTRY(glGetShaderiv),
    ENTRY(glGetShaderInfoLog),
    ENTRY(glCreateProgram),
    ENTRY(glAttachShader),
    ENTRY(glLinkProgram),
    ENTRY(glGetProgramiv),
    ENTRY(glGetProgramInfoLog),
    ENTRY(glUseProgram),
    ENTRY(glDeleteShader),
    ENTRY(glDeleteProgram),
    ENTRY(glGenTextures),
    ENTRY(glBindTexture),
    ENTRY(glActiveTexture),
    ENTRY(glDrawBuffers),
    ENTRY(glBindImageTexture),
    ENTRY(glDispatchCompute),
    ENTRY(glDeleteTextures),
    ENTRY(glTexImage2D),
    ENTRY(glTexImage3D),
    ENTRY(glTexStorage2D),
    ENTRY(glTexStorage3D),
    ENTRY(glTexSubImage3D),
    ENTRY(glCompressedTexImage3D),
    ENTRY(glCompressedTexSubImage3D),
    ENTRY(glFramebufferTextureLayer),
    ENTRY(glCopyImageSubDataEXT),
    ENTRY(glCopyImageSubDataOES),
    ENTRY(glCopyTexSubImage2D),
    ENTRY(glCopyTexSubImage3D),
    ENTRY(glMemoryBarrier),

    ENTRY(glCompressedTexImage2D),
    ENTRY(glTexSubImage2D),
    ENTRY(glCompressedTexSubImage2D),
    ENTRY(glGenerateMipmap),
    ENTRY(glGenRenderbuffers),
    ENTRY(glBindRenderbuffer),
    ENTRY(glRenderbufferStorage),
    ENTRY(glDeleteRenderbuffers),
    ENTRY(glGenFramebuffers),
    ENTRY(glBindFramebuffer),
    ENTRY(glFramebufferTexture2D),
    ENTRY(glFramebufferRenderbuffer),
    ENTRY(glCheckFramebufferStatus),
    ENTRY(glDeleteFramebuffers),
    ENTRY(glGenBuffers),
    ENTRY(glBindBuffer),
    ENTRY(glBufferData),
    ENTRY(glDeleteBuffers),
    ENTRY(glReadPixels),
    ENTRY(glDrawArrays),
    ENTRY(glDrawElements),
    ENTRY(glClear),
    ENTRY(glFlush),
    ENTRY(glGetUniformLocation),
    ENTRY(glGetAttribLocation),
};
#undef ENTRY

static struct TraceEntry *entryFor(const char *name)
{
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); ++i)
        if (!strcmp(entries[i].name, name)) return &entries[i];
    return NULL;
}

__attribute__((constructor)) static void traceLoaded(void)
{
    char exe[4096];
    uint32_t size = sizeof(exe);
    const char *path = _NSGetExecutablePath(exe, &size) == 0 ? exe : "(unavailable)";
    LOG("loaded; waiting for GL symbol resolution pid=%ld executable=%s\n", (long)getpid(), path);
}

static void *realFn(const char *name)
{
    struct TraceEntry *entry = entryFor(name);
    void *fn = entry ? atomic_load(&entry->real) : NULL;
    if (fn) return fn;
    // Calls made by the interposer itself retain the original dlsym binding.
    fn = dlsym(RTLD_NEXT, name);
    if (fn) return fn;
    char exe[4096];
    uint32_t sz = sizeof(exe);
    if (_NSGetExecutablePath(exe, &sz) == 0) {
        char *filename = strrchr(exe, '/');
        if (filename) {
            *filename = '\0';
            char *macos = strrchr(exe, '/');
            if (macos) {
                *macos = '\0'; // .../Contents (remove MacOS as well)
                char path[4096];
                int n = snprintf(path, sizeof(path), "%s/Frameworks/mvk-angle/libGLESv2.dylib", exe);
                void *h = n > 0 && (size_t)n < sizeof(path) ? dlopen(path, RTLD_NOW | RTLD_GLOBAL) : NULL;
                if (h) fn = dlsym(h, name);
            }
        }
    }
    if (!fn) {
        LOG("FATAL: cannot resolve %s\n", name);
        abort();
    }
    return fn;
}

static _Atomic(void *) realEglGetProcAddress;

static void *wrapGL(const char *name, void *fn)
{
    struct TraceEntry *entry = entryFor(name);
    if (!entry || !fn || fn == entry->wrapper) return fn;
    void *previous = atomic_exchange(&entry->real, fn);
    if (previous != fn) {
        Dl_info info = {0};
        dladdr(fn, &info);
        LOG("bind %s -> %p image=%s symbol=%s\n", name, fn,
            info.dli_fname ? info.dli_fname : "?", info.dli_sname ? info.dli_sname : "?");
    }
    return entry->wrapper;
}

static void *traceEglGetProcAddress(const char *name)
{
    void *(*resolve)(const char *) = atomic_load(&realEglGetProcAddress);
    void *fn = resolve(name);
    LOG("resolve eglGetProcAddress name=%s result=%p caller=%p\n",
        name, fn, __builtin_return_address(0));
    return wrapGL(name, fn);
}

static void *traceDlsym(void *handle, const char *name)
{
    void *fn = dlsym(handle, name);
    if (name[0] == 'g' && name[1] == 'l')
        LOG("resolve dlsym name=%s result=%p caller=%p\n",
            name, fn, __builtin_return_address(0));
    if (fn && !strcmp(name, "eglGetProcAddress")) {
        atomic_store(&realEglGetProcAddress, fn);
        LOG("intercepted eglGetProcAddress\n");
        return (void *)traceEglGetProcAddress;
    }
    return wrapGL(name, fn);
}

// Mach-O interposition catches imported dlsym calls with two-level namespaces.
// Exported GL names do not catch handle-specific lookups.
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *replacee; } interposeDlsym = {
    (const void *)traceDlsym, (const void *)dlsym
};

static const char *queryName(GLenum p)
{
    switch (p) {
        case GL_MAX_COLOR_ATTACHMENTS: return "MAX_COLOR_ATTACHMENTS";
        case GL_MAX_DRAW_BUFFERS: return "MAX_DRAW_BUFFERS";
        case GL_MAX_RENDERBUFFER_SIZE: return "MAX_RENDERBUFFER_SIZE";
        case GL_MAX_TEXTURE_SIZE: return "MAX_TEXTURE_SIZE";
        case GL_MAX_SAMPLES: return "MAX_SAMPLES";
        case GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS: return "MAX_VERTEX_TEXTURE_IMAGE_UNITS";
        case GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS: return "MAX_COMBINED_TEXTURE_IMAGE_UNITS";
        case GL_MAX_FRAGMENT_UNIFORM_VECTORS: return "MAX_FRAGMENT_UNIFORM_VECTORS";
        case GL_MAX_VARYING_VECTORS: return "MAX_VARYING_VECTORS";
        case GL_MAX_VERTEX_ATTRIBS: return "MAX_VERTEX_ATTRIBS";
        case 0x846F: return "MAX_TEXTURE_MAX_ANISOTROPY_EXT";
        case GL_FRAGMENT_SHADER_DERIVATIVE_HINT: return "FRAGMENT_SHADER_DERIVATIVE_HINT";
        case GL_NUM_SHADER_BINARY_FORMATS: return "NUM_SHADER_BINARY_FORMATS";
        case GL_IMPLEMENTATION_COLOR_READ_FORMAT: return "IMPLEMENTATION_COLOR_READ_FORMAT";
        case GL_IMPLEMENTATION_COLOR_READ_TYPE: return "IMPLEMENTATION_COLOR_READ_TYPE";
        default: return NULL;
    }
}

const GLubyte *glGetString(GLenum name)
{
    void *caller = __builtin_return_address(0);
    static const GLubyte *(*real)(GLenum) = NULL;
    if (!real) real = (const GLubyte *(*)(GLenum))realFn("glGetString");
    const GLubyte *r = real(name);
    const char *n = NULL;
    switch (name) {
        case GL_VENDOR: n = "VENDOR"; break;
        case GL_RENDERER: n = "RENDERER"; break;
        case GL_VERSION: n = "VERSION"; break;
        case GL_SHADING_LANGUAGE_VERSION: n = "SHADING_LANGUAGE_VERSION"; break;
        case GL_EXTENSIONS: n = "EXTENSIONS"; break;
    }
    if (n) LOG("glGetString(%s) -> %s caller=%p\n", n, r ? (const char *)r : "(null)", caller);
    else LOG("glGetString(0x%x) -> %s caller=%p\n", name, r ? (const char *)r : "(null)", caller);
    return r;
}

const GLubyte *glGetStringi(GLenum name, GLuint index)
{
    void *caller = __builtin_return_address(0);
    static const GLubyte *(*real)(GLenum, GLuint) = NULL;
    if (!real) real = (const GLubyte *(*)(GLenum, GLuint))realFn("glGetStringi");
    const GLubyte *r = real(name, index);
    LOG("glGetStringi(0x%x,%u) -> %s caller=%p\n", name, index, r ? (const char *)r : "(null)", caller);
    return r;
}

void glGetIntegerv(GLenum p, GLint *out)
{
    void *caller = __builtin_return_address(0);
    static void (*real)(GLenum, GLint *) = NULL;
    if (!real) real = (void (*)(GLenum, GLint *))realFn("glGetIntegerv");
    real(p, out);
    const char *n = queryName(p);
    if (!out) LOG("glGetIntegerv(0x%x) -> null caller=%p\n", p, caller);
    else if (n) LOG("glGetIntegerv(%s) -> %d caller=%p\n", n, out[0], caller);
    else LOG("glGetIntegerv(0x%x) -> %d caller=%p\n", p, out[0], caller);
}

void glGetInternalformativ(GLenum target, GLenum internalformat, GLenum pname, GLsizei bufSize, GLint *params)
{
    static void (*real)(GLenum, GLenum, GLenum, GLsizei, GLint *) = NULL;
    if (!real) real = (void (*)(GLenum, GLenum, GLenum, GLsizei, GLint *))realFn("glGetInternalformativ");
    real(target, internalformat, pname, bufSize, params);
    LOG("glGetInternalformativ(target=0x%x format=0x%x pname=0x%x bufSize=%d params=%p)\n",
        target, internalformat, pname, bufSize, (void *)params);
    GLsizei count = params && bufSize > 0 ? (bufSize < 32 ? bufSize : 32) : 0;
    for (GLsizei i = 0; i < count; ++i) LOG("    [%d] = %d\n", i, params[i]);
    if (bufSize > count && params) LOG("    ... %d remaining values omitted\n", bufSize - count);
}

void glGetFloatv(GLenum p, GLfloat *out)
{
    static void (*real)(GLenum, GLfloat *) = NULL;
    if (!real) real = (void (*)(GLenum, GLfloat *))realFn("glGetFloatv");
    real(p, out);
    const char *n = queryName(p);
    LOG("glGetFloatv(%s) -> %f\n", n ? n : "?", out[0]);
}

GLenum glGetError(void)
{
    static GLenum (*real)(void) = NULL;
    if (!real) real = (GLenum (*)(void))realFn("glGetError");
    GLenum e = real();
    if (e != GL_NONE) LOG("glGetError -> 0x%x\n", e);
    return e;
}

void glGetShaderPrecisionFormat(GLenum shadertype, GLenum precisiontype, GLint *range, GLint *precision)
{
    static void (*real)(GLenum, GLenum, GLint *, GLint *) = NULL;
    if (!real) real = (void (*)(GLenum, GLenum, GLint *, GLint *))realFn("glGetShaderPrecisionFormat");
    real(shadertype, precisiontype, range, precision);
    const char *st = shadertype == GL_FRAGMENT_SHADER ? "FRAGMENT" : (shadertype == GL_VERTEX_SHADER ? "VERTEX" : "?");
    const char *pt = precisiontype == GL_HIGH_FLOAT ? "HIGH_FLOAT" : (precisiontype == GL_MEDIUM_FLOAT ? "MEDIUM_FLOAT" : (precisiontype == GL_LOW_FLOAT ? "LOW_FLOAT" : (precisiontype == GL_HIGH_INT ? "HIGH_INT" : "?")));
    LOG("glGetShaderPrecisionFormat(%s,%s) -> range=[%d,%d] precision=%d\n", st, pt, range[0], range[1], precision[0]);
}

GLuint glCreateShader(GLenum type)
{
    static GLuint (*real)(GLenum) = NULL;
    if (!real) real = (GLuint (*)(GLenum))realFn("glCreateShader");
    GLuint r = real(type);
    LOG("glCreateShader(%s) -> %u\n", type == GL_FRAGMENT_SHADER ? "FRAGMENT" : (type == GL_VERTEX_SHADER ? "VERTEX" : "?"), r);
    return r;
}

void glShaderSource(GLuint id, GLsizei count, const GLchar *const *string, const GLint *length)
{
    static void (*real)(GLuint, GLsizei, const GLchar *const *, const GLint *) = NULL;
    if (!real) real = (void (*)(GLuint, GLsizei, const GLchar *const *, const GLint *))realFn("glShaderSource");
    real(id, count, string, length);
    LOG("glShaderSource(%u):\n", id);
    for (int i = 0; i < count; i++) {
        const char *s = string[i];
        // log up to 4000 chars per source
        size_t sourceLen = s ? (length && length[i] >= 0 ? (size_t)length[i] : strlen(s)) : 0;
        size_t len = sourceLen > 4000 ? 4000 : sourceLen;
        for (size_t off = 0; off < len; off += 200) {
            size_t chunk = len - off < 200 ? len - off : 200;
            LOG("    | %.*s\n", (int)chunk, s + off);
        }
        if (sourceLen > 4000) LOG("    | ... (truncated %zu bytes)\n", sourceLen - 4000);
    }
}

void glCompileShader(GLuint id)
{
    static void (*real)(GLuint) = NULL;
    if (!real) real = (void (*)(GLuint))realFn("glCompileShader");
    real(id);
    LOG("glCompileShader(%u)\n", id);
}

void glGetShaderiv(GLuint id, GLenum p, GLint *out)
{
    static void (*real)(GLuint, GLenum, GLint *) = NULL;
    if (!real) real = (void (*)(GLuint, GLenum, GLint *))realFn("glGetShaderiv");
    real(id, p, out);
    const char *n = p == GL_COMPILE_STATUS ? "COMPILE_STATUS" : (p == GL_INFO_LOG_LENGTH ? "INFO_LOG_LENGTH" : (p == GL_DELETE_STATUS ? "DELETE_STATUS" : NULL));
    LOG("glGetShaderiv(%u, %s) -> %d\n", id, n ? n : "?", out[0]);
}

void glGetShaderInfoLog(GLuint id, GLsizei bufSize, GLsizei *length, GLchar *infoLog)
{
    static void (*real)(GLuint, GLsizei, GLsizei *, GLchar *) = NULL;
    if (!real) real = (void (*)(GLuint, GLsizei, GLsizei *, GLchar *))realFn("glGetShaderInfoLog");
    real(id, bufSize, length, infoLog);
    if (infoLog && length && *length > 0) {
        LOG("glGetShaderInfoLog(%u): %.*s\n", id, (int)*length, infoLog);
    }
}

GLuint glCreateProgram(void)
{
    static GLuint (*real)(void) = NULL;
    if (!real) real = (GLuint (*)(void))realFn("glCreateProgram");
    GLuint r = real();
    LOG("glCreateProgram() -> %u\n", r);
    return r;
}

void glAttachShader(GLuint program, GLuint shader)
{
    static void (*real)(GLuint, GLuint) = NULL;
    if (!real) real = (void (*)(GLuint, GLuint))realFn("glAttachShader");
    real(program, shader);
    LOG("glAttachShader(prog=%u, shader=%u)\n", program, shader);
}

void glLinkProgram(GLuint program)
{
    static void (*real)(GLuint) = NULL;
    if (!real) real = (void (*)(GLuint))realFn("glLinkProgram");
    real(program);
    LOG("glLinkProgram(%u)\n", program);
}

void glGetProgramiv(GLuint program, GLenum p, GLint *out)
{
    static void (*real)(GLuint, GLenum, GLint *) = NULL;
    if (!real) real = (void (*)(GLuint, GLenum, GLint *))realFn("glGetProgramiv");
    real(program, p, out);
    const char *n = p == GL_LINK_STATUS ? "LINK_STATUS" : (p == GL_INFO_LOG_LENGTH ? "INFO_LOG_LENGTH" : (p == GL_ACTIVE_UNIFORMS ? "ACTIVE_UNIFORMS" : (p == GL_ACTIVE_ATTRIBUTES ? "ACTIVE_ATTRIBUTES" : NULL)));
    LOG("glGetProgramiv(%u, %s) -> %d\n", program, n ? n : "?", out[0]);
}

void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog)
{
    static void (*real)(GLuint, GLsizei, GLsizei *, GLchar *) = NULL;
    if (!real) real = (void (*)(GLuint, GLsizei, GLsizei *, GLchar *))realFn("glGetProgramInfoLog");
    real(program, bufSize, length, infoLog);
    if (infoLog && length && *length > 0) {
        LOG("glGetProgramInfoLog(%u): %.*s\n", program, (int)*length, infoLog);
    }
}

void glUseProgram(GLuint program)
{
    static void (*real)(GLuint) = NULL;
    if (!real) real = (void (*)(GLuint))realFn("glUseProgram");
    real(program);
    LOG("glUseProgram(%u)\n", program);
}

void glDeleteShader(GLuint id)
{
    static void (*real)(GLuint) = NULL;
    if (!real) real = (void (*)(GLuint))realFn("glDeleteShader");
    real(id);
    LOG("glDeleteShader(%u)\n", id);
}

void glDeleteProgram(GLuint id)
{
    static void (*real)(GLuint) = NULL;
    if (!real) real = (void (*)(GLuint))realFn("glDeleteProgram");
    real(id);
    LOG("glDeleteProgram(%u)\n", id);
}

void glGenTextures(GLsizei n, GLuint *ids)
{
    static void (*real)(GLsizei, GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, GLuint *))realFn("glGenTextures");
    real(n, ids);
    if (n > 0 && ids) LOG("glGenTextures(%d) -> %u\n", n, ids[0]);
    else LOG("glGenTextures(%d) ids=%p\n", n, (void *)ids);
}

void glBindTexture(GLenum target, GLuint texture)
{
    static void (*real)(GLenum, GLuint) = NULL;
    if (!real) real = (void (*)(GLenum, GLuint))realFn("glBindTexture");
    real(target, texture);
    LOG("glBindTexture(0x%x, %u)\n", target, texture);
}

void glDeleteTextures(GLsizei n, const GLuint *ids)
{
    static void (*real)(GLsizei, const GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, const GLuint *))realFn("glDeleteTextures");
    real(n, ids);
    LOG("glDeleteTextures(%d)\n", n);
}

void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei w,
                  GLsizei h, GLint border, GLenum format, GLenum type, const void *data)
{
    static void (*real)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *) = NULL;
    if (!real) real = (void (*)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *))realFn("glTexImage2D");
    real(target, level, internalformat, w, h, border, format, type, data);
    LOG("glTexImage2D target=0x%x level=%d internalformat=0x%x %dx%d fmt=0x%x type=0x%x data=%s\n",
        target, level, internalformat, w, h, format, type, data ? "yes" : "null");
}

void glCompressedTexImage2D(GLenum target, GLint level, GLenum internalformat, GLsizei w,
                            GLsizei h, GLint border, GLsizei imageSize, const void *data)
{
    static void (*real)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei, const void *) = NULL;
    if (!real) real = (void (*)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei, const void *))realFn("glCompressedTexImage2D");
    real(target, level, internalformat, w, h, border, imageSize, data);
    LOG("glCompressedTexImage2D internalformat=0x%x %dx%d\n", internalformat, w, h);
}

void glTexSubImage2D(GLenum target, GLint level, GLint xoff, GLint yoff, GLsizei w, GLsizei h,
                     GLenum format, GLenum type, const void *data)
{
    static void (*real)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void *) = NULL;
    if (!real) real = (void (*)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void *))realFn("glTexSubImage2D");
    real(target, level, xoff, yoff, w, h, format, type, data);
    LOG("glTexSubImage2D %dx%d fmt=0x%x type=0x%x\n", w, h, format, type);
}

void glCompressedTexSubImage2D(GLenum target, GLint level, GLint xoff, GLint yoff, GLsizei w,
                               GLsizei h, GLenum format, GLsizei imageSize, const void *data)
{
    static void (*real)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLsizei, const void *) = NULL;
    if (!real) real = (void (*)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLsizei, const void *))realFn("glCompressedTexSubImage2D");
    real(target, level, xoff, yoff, w, h, format, imageSize, data);
    LOG("glCompressedTexSubImage2D %dx%d fmt=0x%x\n", w, h, format);
}

void glGenerateMipmap(GLenum target)
{
    static void (*real)(GLenum) = NULL;
    if (!real) real = (void (*)(GLenum))realFn("glGenerateMipmap");
    real(target);
    LOG("glGenerateMipmap(0x%x)\n", target);
}

void glGenRenderbuffers(GLsizei n, GLuint *ids)
{
    static void (*real)(GLsizei, GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, GLuint *))realFn("glGenRenderbuffers");
    real(n, ids);
    if (n > 0 && ids) LOG("glGenRenderbuffers(%d) -> %u\n", n, ids[0]);
    else LOG("glGenRenderbuffers(%d) ids=%p\n", n, (void *)ids);
}

void glBindRenderbuffer(GLenum target, GLuint renderbuffer)
{
    static void (*real)(GLenum, GLuint) = NULL;
    if (!real) real = (void (*)(GLenum, GLuint))realFn("glBindRenderbuffer");
    real(target, renderbuffer);
    LOG("glBindRenderbuffer(0x%x, %u)\n", target, renderbuffer);
}

void glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei w, GLsizei h)
{
    static void (*real)(GLenum, GLenum, GLsizei, GLsizei) = NULL;
    if (!real) real = (void (*)(GLenum, GLenum, GLsizei, GLsizei))realFn("glRenderbufferStorage");
    real(target, internalformat, w, h);
    LOG("glRenderbufferStorage internalformat=0x%x %dx%d\n", internalformat, w, h);
}

void glDeleteRenderbuffers(GLsizei n, const GLuint *ids)
{
    static void (*real)(GLsizei, const GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, const GLuint *))realFn("glDeleteRenderbuffers");
    real(n, ids);
    LOG("glDeleteRenderbuffers(%d)\n", n);
}

void glGenFramebuffers(GLsizei n, GLuint *ids)
{
    static void (*real)(GLsizei, GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, GLuint *))realFn("glGenFramebuffers");
    real(n, ids);
    if (n > 0 && ids) LOG("glGenFramebuffers(%d) -> %u\n", n, ids[0]);
    else LOG("glGenFramebuffers(%d) ids=%p\n", n, (void *)ids);
}

void glBindFramebuffer(GLenum target, GLuint framebuffer)
{
    static void (*real)(GLenum, GLuint) = NULL;
    if (!real) real = (void (*)(GLenum, GLuint))realFn("glBindFramebuffer");
    real(target, framebuffer);
    LOG("glBindFramebuffer(0x%x, %u)\n", target, framebuffer);
}

void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget,
                            GLuint texture, GLint level)
{
    static void (*real)(GLenum, GLenum, GLenum, GLuint, GLint) = NULL;
    if (!real) real = (void (*)(GLenum, GLenum, GLenum, GLuint, GLint))realFn("glFramebufferTexture2D");
    real(target, attachment, textarget, texture, level);
    LOG("glFramebufferTexture2D target=0x%x attachment=0x%x textarget=0x%x texture=%u level=%d\n",
        target, attachment, textarget, texture, level);
}

void glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget,
                               GLuint renderbuffer)
{
    static void (*real)(GLenum, GLenum, GLenum, GLuint) = NULL;
    if (!real) real = (void (*)(GLenum, GLenum, GLenum, GLuint))realFn("glFramebufferRenderbuffer");
    real(target, attachment, renderbuffertarget, renderbuffer);
    LOG("glFramebufferRenderbuffer attachment=0x%x rb=%u\n", attachment, renderbuffer);
}

GLenum glCheckFramebufferStatus(GLenum target)
{
    static GLenum (*real)(GLenum) = NULL;
    if (!real) real = (GLenum (*)(GLenum))realFn("glCheckFramebufferStatus");
    GLenum r = real(target);
    LOG("glCheckFramebufferStatus -> 0x%x %s\n", r,
        r == GL_FRAMEBUFFER_COMPLETE ? "(COMPLETE)" : "(INCOMPLETE)");
    return r;
}

void glDeleteFramebuffers(GLsizei n, const GLuint *ids)
{
    static void (*real)(GLsizei, const GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, const GLuint *))realFn("glDeleteFramebuffers");
    real(n, ids);
    LOG("glDeleteFramebuffers(%d)\n", n);
}

void glGenBuffers(GLsizei n, GLuint *ids)
{
    static void (*real)(GLsizei, GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, GLuint *))realFn("glGenBuffers");
    real(n, ids);
    if (n > 0 && ids) LOG("glGenBuffers(%d) -> %u\n", n, ids[0]);
    else LOG("glGenBuffers(%d) ids=%p\n", n, (void *)ids);
}

void glBindBuffer(GLenum target, GLuint buffer)
{
    static void (*real)(GLenum, GLuint) = NULL;
    if (!real) real = (void (*)(GLenum, GLuint))realFn("glBindBuffer");
    real(target, buffer);
    LOG("glBindBuffer(0x%x, %u)\n", target, buffer);
}

void glBufferData(GLenum target, GLsizeiptr size, const void *data, GLenum usage)
{
    static void (*real)(GLenum, GLsizeiptr, const void *, GLenum) = NULL;
    if (!real) real = (void (*)(GLenum, GLsizeiptr, const void *, GLenum))realFn("glBufferData");
    real(target, size, data, usage);
    LOG("glBufferData(0x%x, %d bytes, %s)\n", target, (int)size, data ? "data" : "null");
}

void glDeleteBuffers(GLsizei n, const GLuint *ids)
{
    static void (*real)(GLsizei, const GLuint *) = NULL;
    if (!real) real = (void (*)(GLsizei, const GLuint *))realFn("glDeleteBuffers");
    real(n, ids);
    LOG("glDeleteBuffers(%d)\n", n);
}

void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type,
                  void *pixels)
{
    static void (*real)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *) = NULL;
    if (!real) real = (void (*)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *))realFn("glReadPixels");
    real(x, y, width, height, format, type, pixels);
    LOG("glReadPixels(%d,%d %dx%d fmt=0x%x type=0x%x) caller=%p\n", x, y, width, height, format, type, __builtin_return_address(0));
}

void glDrawArrays(GLenum mode, GLint first, GLsizei count)
{
    static void (*real)(GLenum, GLint, GLsizei) = NULL;
    if (!real) real = (void (*)(GLenum, GLint, GLsizei))realFn("glDrawArrays");
    real(mode, first, count);
    LOG("glDrawArrays(mode=0x%x, count=%d)\n", mode, count);
}

void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices)
{
    static void (*real)(GLenum, GLsizei, GLenum, const void *) = NULL;
    if (!real) real = (void (*)(GLenum, GLsizei, GLenum, const void *))realFn("glDrawElements");
    real(mode, count, type, indices);
    LOG("glDrawElements(mode=0x%x, count=%d)\n", mode, count);
}

void glClear(GLbitfield mask)
{
    static void (*real)(GLbitfield) = NULL;
    if (!real) real = (void (*)(GLbitfield))realFn("glClear");
    real(mask);
    LOG("glClear(0x%x)\n", mask);
}

void glFlush(void)
{
    static void (*real)(void) = NULL;
    if (!real) real = (void (*)(void))realFn("glFlush");
    real();
    LOG("glFlush()\n");
}

GLint glGetUniformLocation(GLuint program, const GLchar *name)
{
    static GLint (*real)(GLuint, const GLchar *) = NULL;
    if (!real) real = (GLint (*)(GLuint, const GLchar *))realFn("glGetUniformLocation");
    GLint r = real(program, name);
    LOG("glGetUniformLocation(%u, \"%s\") -> %d\n", program, name ? name : "(null)", r);
    return r;
}

GLint glGetAttribLocation(GLuint program, const GLchar *name)
{
    static GLint (*real)(GLuint, const GLchar *) = NULL;
    if (!real) real = (GLint (*)(GLuint, const GLchar *))realFn("glGetAttribLocation");
    GLint r = real(program, name);
    LOG("glGetAttribLocation(%u, \"%s\") -> %d\n", program, name ? name : "(null)", r);
    return r;
}

void glActiveTexture(GLenum texture)
{
    static void (*real)(GLenum) = NULL;
    if (!real) real = (void (*)(GLenum))realFn("glActiveTexture");
    real(texture);
    LOG("glActiveTexture(0x%x)\n", texture);
}

void glDrawBuffers(GLsizei count, const GLenum *buffers)
{
    static void (*real)(GLsizei, const GLenum *) = NULL;
    if (!real) real = (void (*)(GLsizei, const GLenum *))realFn("glDrawBuffers");
    real(count, buffers);
    LOG("glDrawBuffers(%d)\n", count);
    for (GLsizei i = 0; buffers && i < count && i < 8; ++i)
        LOG("    drawbuffer[%d]=0x%x\n", i, buffers[i]);
}

void glBindImageTexture(GLuint unit, GLuint texture, GLint level, GLboolean layered,
                        GLint layer, GLenum access, GLenum format)
{
    static void (*real)(GLuint, GLuint, GLint, GLboolean, GLint, GLenum, GLenum) = NULL;
    if (!real) real = (void (*)(GLuint, GLuint, GLint, GLboolean, GLint, GLenum, GLenum))realFn("glBindImageTexture");
    real(unit, texture, level, layered, layer, access, format);
    LOG("glBindImageTexture(unit=%u texture=%u level=%d layered=%u layer=%d access=0x%x format=0x%x)\n",
        unit, texture, level, layered, layer, access, format);
}

void glDispatchCompute(GLuint x, GLuint y, GLuint z)
{
    static void (*real)(GLuint, GLuint, GLuint) = NULL;
    if (!real) real = (void (*)(GLuint, GLuint, GLuint))realFn("glDispatchCompute");
    real(x, y, z);
    LOG("glDispatchCompute(%u,%u,%u)\n", x, y, z);
}

void glTexImage3D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLenum format, GLenum type, const void *pixels)
{
    static PFNGLTEXIMAGE3DPROC real = NULL;
    if (!real) real = (PFNGLTEXIMAGE3DPROC)realFn("glTexImage3D");
    real(target, level, internalformat, width, height, depth, border, format, type, pixels);
    LOG("glTexImage3D(target=0x%x level=%d internalformat=0x%x size=%dx%dx%d border=%d format=0x%x type=0x%x data=%p) caller=%p\n", target, level, internalformat, width, height, depth, border, format, type, pixels, __builtin_return_address(0));
}

void glTexStorage2D(GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height)
{
    static PFNGLTEXSTORAGE2DPROC real = NULL;
    if (!real) real = (PFNGLTEXSTORAGE2DPROC)realFn("glTexStorage2D");
    real(target, levels, internalformat, width, height);
    LOG("glTexStorage2D(target=0x%x levels=%d internalformat=0x%x size=%dx%d) caller=%p\n", target, levels, internalformat, width, height, __builtin_return_address(0));
}

void glTexStorage3D(GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth)
{
    static PFNGLTEXSTORAGE3DPROC real = NULL;
    if (!real) real = (PFNGLTEXSTORAGE3DPROC)realFn("glTexStorage3D");
    real(target, levels, internalformat, width, height, depth);
    LOG("glTexStorage3D(target=0x%x levels=%d internalformat=0x%x size=%dx%dx%d) caller=%p\n", target, levels, internalformat, width, height, depth, __builtin_return_address(0));
}

void glTexSubImage3D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLenum type, const void *pixels)
{
    static PFNGLTEXSUBIMAGE3DPROC real = NULL;
    if (!real) real = (PFNGLTEXSUBIMAGE3DPROC)realFn("glTexSubImage3D");
    real(target, level, xoffset, yoffset, zoffset, width, height, depth, format, type, pixels);
    LOG("glTexSubImage3D(target=0x%x level=%d offset=%d,%d,%d size=%dx%dx%d format=0x%x type=0x%x data=%p) caller=%p\n", target, level, xoffset, yoffset, zoffset, width, height, depth, format, type, pixels, __builtin_return_address(0));
}

void glCompressedTexImage3D(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLsizei imageSize, const void *data)
{
    static PFNGLCOMPRESSEDTEXIMAGE3DPROC real = NULL;
    if (!real) real = (PFNGLCOMPRESSEDTEXIMAGE3DPROC)realFn("glCompressedTexImage3D");
    real(target, level, internalformat, width, height, depth, border, imageSize, data);
    LOG("glCompressedTexImage3D(target=0x%x level=%d internalformat=0x%x size=%dx%dx%d border=%d imageSize=%d data=%p) caller=%p\n", target, level, internalformat, width, height, depth, border, imageSize, data, __builtin_return_address(0));
}

void glCompressedTexSubImage3D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLsizei imageSize, const void *data)
{
    static PFNGLCOMPRESSEDTEXSUBIMAGE3DPROC real = NULL;
    if (!real) real = (PFNGLCOMPRESSEDTEXSUBIMAGE3DPROC)realFn("glCompressedTexSubImage3D");
    real(target, level, xoffset, yoffset, zoffset, width, height, depth, format, imageSize, data);
    LOG("glCompressedTexSubImage3D(target=0x%x level=%d offset=%d,%d,%d size=%dx%dx%d format=0x%x imageSize=%d data=%p) caller=%p\n", target, level, xoffset, yoffset, zoffset, width, height, depth, format, imageSize, data, __builtin_return_address(0));
}

void glFramebufferTextureLayer(GLenum target, GLenum attachment, GLuint texture, GLint level, GLint layer)
{
    static PFNGLFRAMEBUFFERTEXTURELAYERPROC real = NULL;
    if (!real) real = (PFNGLFRAMEBUFFERTEXTURELAYERPROC)realFn("glFramebufferTextureLayer");
    real(target, attachment, texture, level, layer);
    LOG("glFramebufferTextureLayer(target=0x%x attachment=0x%x texture=%u level=%d layer=%d) caller=%p\n", target, attachment, texture, level, layer, __builtin_return_address(0));
}

void glMemoryBarrier(GLbitfield barriers)
{
    static PFNGLMEMORYBARRIERPROC real = NULL;
    if (!real) real = (PFNGLMEMORYBARRIERPROC)realFn("glMemoryBarrier");
    real(barriers);
    LOG("glMemoryBarrier(barriers=0x%x) caller=%p\n", barriers, __builtin_return_address(0));
}

// Copy markers leave GL error state unchanged.
static _Atomic unsigned long gCopyCall;

void glCopyImageSubDataEXT(GLuint srcName, GLenum srcTarget, GLint srcLevel, GLint srcX, GLint srcY, GLint srcZ,
          GLuint dstName, GLenum dstTarget, GLint dstLevel, GLint dstX, GLint dstY, GLint dstZ,
          GLsizei width, GLsizei height, GLsizei depth)
{
    static PFNGLCOPYIMAGESUBDATAEXTPROC real = NULL;
    if (!real) real = (PFNGLCOPYIMAGESUBDATAEXTPROC)realFn("glCopyImageSubDataEXT");
    unsigned long call = atomic_fetch_add(&gCopyCall, 1) + 1;
    void *caller = __builtin_return_address(0);
    LOG("glCopyImageSubDataEXT BEGIN copy=%lu src=%u target=0x%x level=%d xyz=%d,%d,%d dst=%u target=0x%x level=%d xyz=%d,%d,%d size=%dx%dx%d caller=%p\n",
        call, srcName, srcTarget, srcLevel, srcX, srcY, srcZ,
        dstName, dstTarget, dstLevel, dstX, dstY, dstZ, width, height, depth, caller);
    real(srcName, srcTarget, srcLevel, srcX, srcY, srcZ,
         dstName, dstTarget, dstLevel, dstX, dstY, dstZ, width, height, depth);
    LOG("glCopyImageSubDataEXT END copy=%lu caller=%p\n", call, caller);
}

void glCopyImageSubDataOES(GLuint srcName, GLenum srcTarget, GLint srcLevel, GLint srcX, GLint srcY, GLint srcZ,
          GLuint dstName, GLenum dstTarget, GLint dstLevel, GLint dstX, GLint dstY, GLint dstZ,
          GLsizei width, GLsizei height, GLsizei depth)
{
    static PFNGLCOPYIMAGESUBDATAOESPROC real = NULL;
    if (!real) real = (PFNGLCOPYIMAGESUBDATAOESPROC)realFn("glCopyImageSubDataOES");
    unsigned long call = atomic_fetch_add(&gCopyCall, 1) + 1;
    void *caller = __builtin_return_address(0);
    LOG("glCopyImageSubDataOES BEGIN copy=%lu src=%u target=0x%x level=%d xyz=%d,%d,%d dst=%u target=0x%x level=%d xyz=%d,%d,%d size=%dx%dx%d caller=%p\n",
        call, srcName, srcTarget, srcLevel, srcX, srcY, srcZ,
        dstName, dstTarget, dstLevel, dstX, dstY, dstZ, width, height, depth, caller);
    real(srcName, srcTarget, srcLevel, srcX, srcY, srcZ,
         dstName, dstTarget, dstLevel, dstX, dstY, dstZ, width, height, depth);
    LOG("glCopyImageSubDataOES END copy=%lu caller=%p\n", call, caller);
}

void glCopyTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height)
{
    static PFNGLCOPYTEXSUBIMAGE2DPROC real = NULL;
    if (!real) real = (PFNGLCOPYTEXSUBIMAGE2DPROC)realFn("glCopyTexSubImage2D");
    unsigned long call = atomic_fetch_add(&gCopyCall, 1) + 1;
    void *caller = __builtin_return_address(0);
    LOG("glCopyTexSubImage2D BEGIN copy=%lu dst=bound target=0x%x level=%d offset=%d,%d srcFramebufferXY=%d,%d size=%dx%d caller=%p\n", call, target, level, xoffset, yoffset, x, y, width, height, caller);
    real(target, level, xoffset, yoffset, x, y, width, height);
    LOG("glCopyTexSubImage2D END copy=%lu caller=%p\n", call, caller);
}

void glCopyTexSubImage3D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLint x, GLint y, GLsizei width, GLsizei height)
{
    static PFNGLCOPYTEXSUBIMAGE3DPROC real = NULL;
    if (!real) real = (PFNGLCOPYTEXSUBIMAGE3DPROC)realFn("glCopyTexSubImage3D");
    unsigned long call = atomic_fetch_add(&gCopyCall, 1) + 1;
    void *caller = __builtin_return_address(0);
    LOG("glCopyTexSubImage3D BEGIN copy=%lu dst=bound target=0x%x level=%d offset=%d,%d,%d srcFramebufferXY=%d,%d size=%dx%d caller=%p\n", call, target, level, xoffset, yoffset, zoffset, x, y, width, height, caller);
    real(target, level, xoffset, yoffset, zoffset, x, y, width, height);
    LOG("glCopyTexSubImage3D END copy=%lu caller=%p\n", call, caller);
}
