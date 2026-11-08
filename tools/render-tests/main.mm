// Offline GL rendering checks for ANGLE Vulkan and MoltenVK on macOS.
//
// Uses ANGLE from out/angle and the given Vulkan driver for headless GL checks:
//
//   T0  caps: renderer, version, required extensions
//   T1  framebuffer fetch: ESSL 3.10 inout output (water / Snell window path)
//   T2  typed unsigned integer write into GL_RGBA16UI (G-buffer write)
//   T3  deferred round trip: write to RGBA16UI, sample it in a second pass (G-buffer read)
//   T4  fancy sanity: textured quad with depth (regression baseline)
//   T5  typed unsigned integer write into GL_RGBA8UI
//
// Usage: render-tests [path/to/MoltenVK_icd.json]
//        (defaults to ../../out/moltenvk/MoltenVK_icd.json relative to the executable)

#import <Cocoa/Cocoa.h>

#include <EGL/egl.h>
#include <GLES3/gl31.h>
#include <GLES3/gl3platform.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// GL objects use the GLES glGen* and glDelete* entry points.
inline GLuint makeTexture()
{
    GLuint t = 0;
    glGenTextures(1, &t);
    return t;
}
inline void freeTexture(GLuint t) { glDeleteTextures(1, &t); }
inline GLuint makeFramebuffer()
{
    GLuint f = 0;
    glGenFramebuffers(1, &f);
    return f;
}
inline void freeFramebuffer(GLuint f) { glDeleteFramebuffers(1, &f); }
inline GLuint makeRenderbuffer()
{
    GLuint r = 0;
    glGenRenderbuffers(1, &r);
    return r;
}
inline void freeRenderbuffer(GLuint r) { glDeleteRenderbuffers(1, &r); }

// ---------------------------------------------------------------------------
// Small test framework
// ---------------------------------------------------------------------------

static int gFailures = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        if (!(cond)) {                                                          \
            printf("    FAIL: %s\n", msg);                                      \
            gFailures++;                                                        \
            return false;                                                       \
        }                                                                       \
    } while (0)

static const char *gFilter = nullptr;  // if set, only run tests whose name contains this

#define TEST(func)                                                              \
    do {                                                                        \
        if (gFilter && !strstr(#func, gFilter)) break;                          \
        printf("[%s] ", #func);                                                 \
        fflush(stdout);                                                         \
        bool ok = func();                                                       \
        printf("%s\n", ok ? "PASS" : "FAIL");                                   \
        if (!ok) gFailures++;                                                   \
    } while (0)

// ---------------------------------------------------------------------------
// GL helpers
// ---------------------------------------------------------------------------

static const char kVertexShader[] = R"(#version 310 es
layout(location = 0) in vec2 pos;
void main() { gl_Position = vec4(pos, 0.0, 1.0); }
)";

// A full-screen triangle with explicit vertex data.
static GLuint makeFullscreenVAO()
{
    const float verts[6] = {-1.0f, -1.0f, 3.0f, -1.0f, -1.0f, 3.0f};
    GLuint vao = 0;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    GLuint vbo = 0;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
    glEnableVertexAttribArray(0);
    glBindVertexArray(0);
    return vao;
}

static GLuint compileShader(GLenum type, const char *src)
{
    GLuint sh = glCreateShader(type);
    glShaderSource(sh, 1, &src, nullptr);
    glCompileShader(sh);
    GLint ok = 0;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[8192];
        glGetShaderInfoLog(sh, sizeof(log), nullptr, log);
        printf("    shader compile error:\n%s\n", log);
        glDeleteShader(sh);
        return 0;
    }
    return sh;
}

static GLuint makeProgram(const char *fragSrc)
{
    GLuint vs = compileShader(GL_VERTEX_SHADER, kVertexShader);
    GLuint fs = compileShader(GL_FRAGMENT_SHADER, fragSrc);
    if (!vs || !fs) return 0;
    GLuint prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glLinkProgram(prog);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint ok = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[8192];
        glGetProgramInfoLog(prog, sizeof(log), nullptr, log);
        printf("    program link error:\n%s\n", log);
        glDeleteProgram(prog);
        return 0;
    }
    return prog;
}

static GLuint gVao = 0;

// Draws the full-screen triangle with the currently bound program.
static void glDrawTri()
{
    glBindVertexArray(gVao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
}

// Reads the center pixel of the default framebuffer as byte RGBA.
// (ES 3.0: GL_FLOAT readback is only valid from float surfaces; the default
// surface is unorm, so read GL_UNSIGNED_BYTE.)
static bool readCenterPixel(uint8_t out[4])
{
    GLint viewport[4] = {0, 0, 0, 0};
    glGetIntegerv(GL_VIEWPORT, viewport);
    glReadPixels(viewport[0] + viewport[2] / 2, viewport[1] + viewport[3] / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, out);
    GLenum err = glGetError();
    if (err != GL_NONE) printf("    glReadPixels error 0x%x\n", err);
    CHECK(err == GL_NONE, "glReadPixels(default framebuffer)");
    return true;
}

// Read the callee-saved x22 register for ABI checks.
static inline uint64_t peek_x22(void)
{
    uint64_t v;
    asm volatile("mov %0, x22" : "=r"(v));
    return v;
}

static void errCheck(const char *step);

// Read the center pixel of FBO color attachment 0 with the given format and type.
static bool readFboPixelInt(GLuint fbo, GLenum internalFormat, GLenum type, void *out)
{
    volatile uint64_t canary = 0x1122334455667788ULL;
    auto canaryCheck = [&](const char *where) {
        if (canary != 0x1122334455667788ULL)
            printf("    CANARY CORRUPT after %s: 0x%llx\n", where, (unsigned long long)canary);
    };
    auto x22Check = [&](const char *where, uint64_t before) {
        uint64_t after = peek_x22();
        if (after != before)
            printf("    X22 CLOBBER after %s: 0x%llx -> 0x%llx\n", where,
                   (unsigned long long)before, (unsigned long long)after);
    };
    uint64_t x22 = peek_x22();
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    x22Check("glBindFramebuffer", x22);
    errCheck("readFbo:glBindFramebuffer");
    GLint viewport[4] = {0, 0, 0, 0};
    glGetIntegerv(GL_VIEWPORT, viewport);
    x22Check("glGetIntegerv", x22);
    errCheck("readFbo:glGetIntegerv");
    glReadPixels(viewport[0] + viewport[2] / 2, viewport[1] + viewport[3] / 2, 1, 1, internalFormat, type, out);
    x22Check("glReadPixels", x22);
    // Save the read error before other error checks clear it.
    GLenum err = glGetError();
    canaryCheck("glReadPixels");
    x22Check("glGetError", x22);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    x22Check("glBindFramebuffer(0)", x22);
    canaryCheck("end");
    if (err != GL_NONE) printf("    glReadPixels error 0x%x\n", err);
    CHECK(err == GL_NONE, "glReadPixels(FBO)");
    return true;
}

static GLuint makeRgba16uiFbo(int w, int h, GLuint *outTex)
{
    GLuint tex = makeTexture();
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16UI, w, h, 0, GL_RGBA_INTEGER, GL_UNSIGNED_SHORT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    GLuint fbo = makeFramebuffer();
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (rs != GL_FRAMEBUFFER_COMPLETE) {
        printf("    RGBA16UI FBO incomplete: 0x%x\n", rs);
        return 0;
    }
    if (outTex) *outTex = tex;
    return fbo;
}

static GLuint makeRgba8uiFbo(int w, int h, GLuint *outTex)
{
    GLuint tex = makeTexture();
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8UI, w, h, 0, GL_RGBA_INTEGER, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    GLuint fbo = makeFramebuffer();
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (rs != GL_FRAMEBUFFER_COMPLETE) {
        printf("    RGBA8UI FBO incomplete: 0x%x\n", rs);
        return 0;
    }
    if (outTex) *outTex = tex;
    return fbo;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static bool extSupported(const char *name)
{
    const char *exts = (const char *)glGetString(GL_EXTENSIONS);
    if (!exts) return false;
    // Extensions are whitespace separated.
    std::string s(exts);
    std::string tok;
    size_t i = 0;
    while (i < s.size()) {
        while (i < s.size() && isspace((unsigned char)s[i])) i++;
        size_t start = i;
        while (i < s.size() && !isspace((unsigned char)s[i])) i++;
        if (s.compare(start, i - start, name) == 0) return true;
    }
    return false;
}

static bool run_T0_caps()
{
    const char *ver = (const char *)glGetString(GL_VERSION);
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *slVer = (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION);
    printf("    GL_VERSION=%s\n    GL_RENDERER=%s\n    GLSL=%s\n", ver ? ver : "?",
           renderer ? renderer : "?", slVer ? slVer : "?");
    CHECK(ver && strstr(ver, "3."), "ES 3.x context");

    const char *required[] = {
        "GL_EXT_shader_framebuffer_fetch",
        "GL_OES_texture_float_linear",
        "GL_EXT_color_buffer_float",
    };
    for (const char *e : required) {
        printf("    %-40s %s\n", e, extSupported(e) ? "yes" : "NO");
    }
    printf("    GL_ANGLE_robust_fragment_shader_output %s\n",
           extSupported("GL_ANGLE_robust_fragment_shader_output") ? "yes" : "NO");
    return true;
}

// Pass 1 writes a known color, pass 2 fetches through an ESSL 3.10 inout output.
// If framebuffer fetch works, the pixel is unchanged.
static bool run_T1_framebuffer_fetch()
{
    static const char *kPass1[] = {
        "#version 310 es\nprecision highp float;\nout vec4 c;\n"
        "void main() { c = vec4(1.0, 0.25, 0.5, 1.0); }\n"};
    // EXT_shader_framebuffer_fetch uses inout outputs with ESSL 3.00+;
    // gl_LastFragData belongs to the extension's ESSL 1.00 interface.
    static const char *kPass2[] = {
        "#version 310 es\n"
        "#extension GL_EXT_shader_framebuffer_fetch : require\n"
        "precision highp float;\n"
        "layout(location = 0) inout highp vec4 c;\n"
        "void main() { c = vec4(c.rgb, 1.0); }\n"};

    GLuint p1 = makeProgram(kPass1[0]);
    CHECK(p1 != 0, "compile pass 1");
    GLuint p2 = makeProgram(kPass2[0]);
    CHECK(p2 != 0, "compile pass 2 (requires GL_EXT_shader_framebuffer_fetch)");
    if (!p1 || !p2) return false;

    glUseProgram(p1); glDrawTri(); glUseProgram(0);
    glUseProgram(p2); glDrawTri(); glUseProgram(0);
    glFlush();

    uint8_t px[4] = {0xff, 0xff, 0xff, 0xff};
    if (!readCenterPixel(px)) return false;
    printf("    readback: (%u, %u, %u, %u), expected (255, 64, 128, 255)\n",
           px[0], px[1], px[2], px[3]);
    bool ok = px[0] >= 254 && px[1] >= 63 && px[1] <= 65 && px[2] >= 127 && px[2] <= 129 &&
              px[3] >= 254;
    glDeleteProgram(p1);
    glDeleteProgram(p2);
    return ok;
}

// Check which integer color formats form a complete FBO.
static bool run_T2b_renderable_formats()
{
    struct { const char *name; GLenum internal; GLenum format; GLenum type; } fmts[] = {
        {"GL_RGBA8UI",   GL_RGBA8UI,   GL_RGBA_INTEGER, GL_UNSIGNED_BYTE},
        {"GL_RGBA16UI",  GL_RGBA16UI,  GL_RGBA_INTEGER, GL_UNSIGNED_SHORT},
        {"GL_RGBA32UI",  GL_RGBA32UI,  GL_RGBA_INTEGER, GL_UNSIGNED_INT},
        {"GL_RGBA8I",    GL_RGBA8I,    GL_RGBA_INTEGER, GL_BYTE},
        {"GL_RGBA16I",   GL_RGBA16I,   GL_RGBA_INTEGER, GL_SHORT},
        {"GL_RGBA32I",   GL_RGBA32I,   GL_RGBA_INTEGER, GL_INT},
        {"GL_R16UI",     GL_R16UI,     GL_RED_INTEGER,  GL_UNSIGNED_SHORT},
        {"GL_RG16UI",    GL_RG16UI,    GL_RG_INTEGER,   GL_UNSIGNED_SHORT},
        {"GL_RGBA16F",   GL_RGBA16F,   GL_RGBA,         GL_FLOAT},
        {"GL_RGBA32F",   GL_RGBA32F,   GL_RGBA,         GL_FLOAT},
    };
    bool anyInt = false;
    for (auto &f : fmts) {
        GLuint tex = makeTexture();
        glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, f.internal, 4, 4, 0, f.format, f.type, nullptr);
        GLenum texErr = glGetError();
        if (texErr != GL_NONE) printf("    %-12s glTexImage2D error 0x%x\n", f.name, texErr);
        GLuint fbo = makeFramebuffer();
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
        GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        bool ok = (rs == GL_FRAMEBUFFER_COMPLETE);
        if (ok && f.internal != GL_RGBA16F && f.internal != GL_RGBA32F) anyInt = true;
        printf("    %-12s %s\n", f.name, ok ? "COMPLETE" : "incomplete");
        freeTexture(tex);
        freeFramebuffer(fbo);
    }
    printf("    at least one integer format renderable: %s\n", anyInt ? "yes" : "NO");
    return anyInt;
}

// ES 3.1 section 14.2.3 requires matching output/attachment component types.
// Check exact unsigned integer values. Float output to an integer attachment
// has undefined results.
static bool run_T2_uint_rgba16ui()
{
    static const char *kShader[] = {
        "#version 310 es\nprecision highp int;\nlayout(location = 0) out highp uvec4 c;\n"
        "uniform highp uvec4 color;\n"
        "void main() { c = color; }\n"};
    GLuint prog = makeProgram(kShader[0]);
    CHECK(prog != 0, "compile shader");
    if (!prog) return false;
    GLint colorLoc = glGetUniformLocation(prog, "color");

    GLuint fbo = makeRgba16uiFbo(64, 64, nullptr);
    CHECK(fbo != 0, "create RGBA16UI FBO");
    if (!fbo) { glDeleteProgram(prog); return false; }

    struct { GLuint in[4]; uint32_t out[4]; } cases[] = {
        {{0, 3, 0, 0}, {0, 3, 0, 0}},
        {{65535, 0, 65535, 65535}, {65535, 0, 65535, 65535}},
    };

    GLint savedViewport[4];
    glGetIntegerv(GL_VIEWPORT, savedViewport);
    bool ok = true;
    for (auto &c : cases) {
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glViewport(0, 0, 64, 64);
        const GLuint clear[4] = {0, 0, 0, 0};
        glClearBufferuiv(GL_COLOR, 0, clear);
        glUseProgram(prog);
        glUniform4uiv(colorLoc, 1, c.in);
        glDrawTri();
        glUseProgram(0);
        glFlush();

        uint32_t px[4] = {0, 0, 0, 0};
        if (!readFboPixelInt(fbo, GL_RGBA_INTEGER, GL_UNSIGNED_INT, px)) { ok = false; break; }
        printf("    in (%u, %u, %u, %u) -> out (%u, %u, %u, %u), expected (%u, %u, %u, %u)\n",
               c.in[0], c.in[1], c.in[2], c.in[3], px[0], px[1], px[2], px[3],
               c.out[0], c.out[1], c.out[2], c.out[3]);
        for (int i = 0; i < 4; i++) {
            if (px[i] != c.out[i]) { ok = false; break; }
        }
        if (!ok) break;
    }

    glViewport(savedViewport[0], savedViewport[1], savedViewport[2], savedViewport[3]);
    freeFramebuffer(fbo);
    glDeleteProgram(prog);
    return ok;
}

// Deferred round trip: write matching uvec4 data into an RGBA16UI G-buffer,
// then verify every sampled integer component in a second shader pass.
static bool run_T3_deferred_roundtrip()
{
    static const char *kWrite[] = {
        "#version 310 es\nprecision highp int;\nlayout(location = 0) out highp uvec4 c;\n"
        "uniform highp uvec4 color;\n"
        "void main() { c = color; }\n"};
    static const char *kSample[] = {
        "#version 310 es\nprecision highp float;\nprecision highp usampler2D;\nout vec4 c;\n"
        "uniform usampler2D tex;\n"
        "uniform highp uvec4 expected;\n"
        "uniform vec2 uv;\n"
        "void main() { c = vec4(equal(texture(tex, uv), expected)); }\n"};

    GLuint writer = makeProgram(kWrite[0]);
    GLuint sampler = makeProgram(kSample[0]);
    CHECK(writer != 0 && sampler != 0, "compile shaders");
    if (!writer || !sampler) return false;

    const GLuint in[4] = {100, 201, 300, 401};
    const uint32_t expected[4] = {100, 201, 300, 401};

    GLuint tex = 0;
    GLuint fbo = makeRgba16uiFbo(64, 64, &tex);
    CHECK(fbo != 0, "create RGBA16UI FBO");
    if (!fbo) { glDeleteProgram(writer); glDeleteProgram(sampler); return false; }

    GLint defaultViewport[4];
    glGetIntegerv(GL_VIEWPORT, defaultViewport);
    // Pass 1: write typed unsigned integer data into the G-buffer.
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glViewport(0, 0, 64, 64);
    const GLuint clear[4] = {0, 0, 0, 0};
    glClearBufferuiv(GL_COLOR, 0, clear);
    glUseProgram(writer);
    glUniform4uiv(glGetUniformLocation(writer, "color"), 1, in);
    glDrawTri();
    glUseProgram(0);
    glFlush();

    // Read the G-buffer back directly (valid: uint surface + GL_RGBA_INTEGER/
    // GL_UNSIGNED_INT per ES 3.0). Verifies exact integer storage.
    uint32_t px[4] = {0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff};
    if (!readFboPixelInt(fbo, GL_RGBA_INTEGER, GL_UNSIGNED_INT, px)) {
        glViewport(defaultViewport[0], defaultViewport[1], defaultViewport[2], defaultViewport[3]);
        freeFramebuffer(fbo);
        freeTexture(tex);
        glDeleteProgram(writer);
        glDeleteProgram(sampler);
        return false;
    }

    // Pass 2: output one per matching component, zero per mismatch. This
    // keeps the integer values from being clamped by the unorm framebuffer.
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(defaultViewport[0], defaultViewport[1], defaultViewport[2], defaultViewport[3]);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex);
    glUseProgram(sampler);
    glUniform1i(glGetUniformLocation(sampler, "tex"), 0);
    glUniform4uiv(glGetUniformLocation(sampler, "expected"), 1, expected);
    glUniform2f(glGetUniformLocation(sampler, "uv"), 0.5f, 0.5f);
    glDrawTri();
    glUseProgram(0);
    glFlush();
    uint8_t sampled[4] = {0, 0, 0, 0};
    bool sampleReadOk = readCenterPixel(sampled);

    printf("    write (%u, %u, %u, %u), gbuffer (%u, %u, %u, %u), expected (%u, %u, %u, %u)\n",
           in[0], in[1], in[2], in[3], px[0], px[1], px[2], px[3],
           expected[0], expected[1], expected[2], expected[3]);

    bool ok = sampleReadOk;
    for (int i = 0; i < 4; i++) {
        if (px[i] != expected[i] || sampled[i] != 255) { ok = false; break; }
    }
    printf("    sampled component matches: (%u, %u, %u, %u), expected all 255\n",
           sampled[0], sampled[1], sampled[2], sampled[3]);

    freeFramebuffer(fbo);
    freeTexture(tex);
    glDeleteProgram(writer);
    glDeleteProgram(sampler);
    return ok;
}

// A textured RGBA8 draw with a depth buffer for forward rendering checks.
static bool run_T4_fancy_sanity()
{
    static const char *kShader[] = {
        "#version 310 es\nprecision highp float;\nout vec4 c;\n"
        "uniform sampler2D tex;\n"
        "uniform vec2 uv;\n"
        "void main() { c = texture(tex, uv); }\n"};

    // 2x2 texture: red, green / blue, white
    const uint8_t pixels[16] = {
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   255, 255, 255, 255,
    };
    GLuint tex = makeTexture();
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    GLuint rbo = makeRenderbuffer();
    glBindRenderbuffer(GL_RENDERBUFFER, rbo);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, 64, 64);

    GLuint fbo = makeFramebuffer();
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, rbo);
    // The FBO has its own color texture for drawing and readback.
    GLuint colorTex = makeTexture();
    glBindTexture(GL_TEXTURE_2D, colorTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorTex, 0);
    GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    CHECK(rs == GL_FRAMEBUFFER_COMPLETE, "FBO complete");
    if (rs != GL_FRAMEBUFFER_COMPLETE) return false;

    GLuint prog = makeProgram(kShader[0]);
    CHECK(prog != 0, "compile shader");
    if (!prog) return false;

    glViewport(0, 0, 64, 64);
    // Bind the source texture for sampling. The draw target is a separate texture.
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex);
    glUseProgram(prog);
    glUniform1i(glGetUniformLocation(prog, "tex"), 0);
    glUniform2f(glGetUniformLocation(prog, "uv"), 0.25f, 0.25f);  // top-left texel = red
    glDrawTri();
    glUseProgram(0);
    glFlush();

    // Unorm surface: read GL_UNSIGNED_BYTE (ES 3.0 forbids GL_FLOAT here).
    uint8_t px[4] = {0, 0, 0, 0};
    if (!readFboPixelInt(fbo, GL_RGBA, GL_UNSIGNED_BYTE, px)) return false;
    printf("    sampled red texel: (%u, %u, %u, %u)\n", px[0], px[1], px[2], px[3]);
    bool ok = px[0] > 230 && px[1] < 25 && px[2] < 25 && px[3] > 230;

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    freeFramebuffer(fbo);
    freeRenderbuffer(rbo);
    freeTexture(colorTex);
    freeTexture(tex);
    glDeleteProgram(prog);
    return ok;
}

// Print and clear a pending GL error with the caller's step name.
static void errCheck(const char *step)
{
    GLenum e = glGetError();
    if (e != GL_NONE) {
        printf("    ERROR 0x%x after %s\n", e, step);
    }
}

// Readback type/attachment compatibility checks (ES 3.0 rules):
//  a) color-only unorm FBO, GL_RGBA/GL_UNSIGNED_BYTE read
//  b) depth FBO, GL_RGBA/GL_UNSIGNED_BYTE read
//  c) float FBO (RGBA16F), GL_RGBA/GL_FLOAT read (valid float readback)
static bool run_T4b_readback_variants()
{
    // a) color-only FBO, GL_RGBA/GL_UNSIGNED_BYTE read
    {
        GLuint tex = makeTexture();
        glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        GLuint fbo = makeFramebuffer();
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
        GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        CHECK(rs == GL_FRAMEBUFFER_COMPLETE, "T4b-a FBO complete");
        uint32_t px[4] = {0, 0, 0, 0};
        bool ok = readFboPixelInt(fbo, GL_RGBA, GL_UNSIGNED_BYTE, px);
        printf("    T4b-a color-only FBO byte read: %s\n", ok ? "OK" : "ERR");
        freeFramebuffer(fbo);
        freeTexture(tex);
        if (!ok) return false;
    }
    // b) depth FBO, GL_RGBA/GL_UNSIGNED_BYTE read
    {
        GLuint rbo = makeRenderbuffer();
        glBindRenderbuffer(GL_RENDERBUFFER, rbo);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, 64, 64);
        GLuint tex = makeTexture();
        glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        GLuint fbo = makeFramebuffer();
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, rbo);
        GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        CHECK(rs == GL_FRAMEBUFFER_COMPLETE, "T4b-b FBO complete");
        uint32_t px[4] = {0, 0, 0, 0};
        bool ok = readFboPixelInt(fbo, GL_RGBA, GL_UNSIGNED_BYTE, px);
        printf("    T4b-b depth FBO byte read: %s\n", ok ? "OK" : "ERR");
        freeFramebuffer(fbo);
        freeRenderbuffer(rbo);
        freeTexture(tex);
        if (!ok) return false;
    }
    // c) float FBO (RGBA16F), GL_RGBA/GL_FLOAT read
    {
        GLuint tex = makeTexture();
        glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, 64, 64, 0, GL_RGBA, GL_HALF_FLOAT, nullptr);
        GLuint fbo = makeFramebuffer();
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
        GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        CHECK(rs == GL_FRAMEBUFFER_COMPLETE, "T4b-c FBO complete");
        float px[4] = {0, 0, 0, 0};
        bool ok = readFboPixelInt(fbo, GL_RGBA, GL_FLOAT, px);
        printf("    T4b-c float FBO float read: %s\n", ok ? "OK" : "ERR");
        freeFramebuffer(fbo);
        freeTexture(tex);
        if (!ok) return false;
    }
    return true;
}

// Exact typed writes into 8-bit integer storage; catches unorm/uint confusion.
static bool run_T5_uint_rgba8ui()
{
    static const char *kShader[] = {
        "#version 310 es\nprecision highp int;\nlayout(location = 0) out highp uvec4 c;\n"
        "uniform highp uvec4 color;\n"
        "void main() { c = color; }\n"};
    GLuint prog = makeProgram(kShader[0]);
    CHECK(prog != 0, "compile shader");
    if (!prog) return false;
    GLint colorLoc = glGetUniformLocation(prog, "color");

    GLuint fbo = makeRgba8uiFbo(64, 64, nullptr);
    CHECK(fbo != 0, "create RGBA8UI FBO");
    if (!fbo) { glDeleteProgram(prog); return false; }

    struct { GLuint in[4]; uint32_t out[4]; } cases[] = {
        {{1, 1, 2, 0}, {1, 1, 2, 0}},
        {{100, 0, 1, 1}, {100, 0, 1, 1}},
    };

    GLint savedViewport[4];
    glGetIntegerv(GL_VIEWPORT, savedViewport);
    bool ok = true;
    for (auto &c : cases) {
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glViewport(0, 0, 64, 64);
        const GLuint clear[4] = {0, 0, 0, 0};
        glClearBufferuiv(GL_COLOR, 0, clear);
        glUseProgram(prog);
        glUniform4uiv(colorLoc, 1, c.in);
        glDrawTri();
        glUseProgram(0);
        glFlush();

        uint32_t px[4] = {0, 0, 0, 0};
        if (!readFboPixelInt(fbo, GL_RGBA_INTEGER, GL_UNSIGNED_INT, px)) { ok = false; break; }
        printf("    in (%u, %u, %u, %u) -> out (%u, %u, %u, %u), expected (%u, %u, %u, %u)\n",
               c.in[0], c.in[1], c.in[2], c.in[3], px[0], px[1], px[2], px[3],
               c.out[0], c.out[1], c.out[2], c.out[3]);
        for (int i = 0; i < 4; i++) {
            if (px[i] != c.out[i]) { ok = false; break; }
        }
        if (!ok) break;
    }

    glViewport(savedViewport[0], savedViewport[1], savedViewport[2], savedViewport[3]);
    freeFramebuffer(fbo);
    glDeleteProgram(prog);
    return ok;
}

// Print extensions and render target limits. Check a float MRT FBO and a
// depth attachment.
static bool run_T6_capability_dump()
{
    printf("    --- full GL_EXTENSIONS ---\n");
    const char *exts = (const char *)glGetString(GL_EXTENSIONS);
    if (exts) {
        std::string s(exts);
        for (size_t i = 0; i < s.size();) {
            while (i < s.size() && isspace((unsigned char)s[i])) i++;
            size_t start = i;
            while (i < s.size() && !isspace((unsigned char)s[i])) i++;
            if (i > start) printf("      %s\n", s.substr(start, i - start).c_str());
        }
    } else {
        printf("      (none)\n");
    }

    GLint maxColor = 0, maxDraw = 0, maxRB = 0, maxTex = 0;
    glGetIntegerv(GL_MAX_COLOR_ATTACHMENTS, &maxColor);
    glGetIntegerv(GL_MAX_DRAW_BUFFERS, &maxDraw);
    glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE, &maxRB);
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTex);
    printf("    GL_MAX_COLOR_ATTACHMENTS=%d  GL_MAX_DRAW_BUFFERS=%d\n", maxColor, maxDraw);
    printf("    GL_MAX_RENDERBUFFER_SIZE=%d  GL_MAX_TEXTURE_SIZE=%d\n", maxRB, maxTex);

    // MRT test: two RGBA16F color attachments on one FBO.
    GLuint texA = makeTexture(), texB = makeTexture();
    for (GLuint t : {texA, texB}) {
        glBindTexture(GL_TEXTURE_2D, t);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, 4, 4, 0, GL_RGBA, GL_FLOAT, nullptr);
    }
    GLuint fbo = makeFramebuffer();
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texA, 0);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, texB, 0);
    GLenum rs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    printf("    MRT (2x RGBA16F) FBO: %s\n", rs == GL_FRAMEBUFFER_COMPLETE ? "COMPLETE" : "incomplete");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    freeTexture(texA); freeTexture(texB); freeFramebuffer(fbo);

    // Depth renderability: renderbuffer depth24.
    GLuint rb = 0;
    glGenRenderbuffers(1, &rb);
    glBindRenderbuffer(GL_RENDERBUFFER, rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, 4, 4);
    GLuint dfbo = makeFramebuffer();
    glBindFramebuffer(GL_FRAMEBUFFER, dfbo);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, rb);
    GLenum drs = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    printf("    depth24 renderbuffer FBO: %s\n", drs == GL_FRAMEBUFFER_COMPLETE ? "COMPLETE" : "incomplete");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteRenderbuffers(1, &rb);
    freeFramebuffer(dfbo);

    return true;
}

// Verify the normalized 16-bit storage needed by packed normal/depth data.
// Float shader output and sampler2D must preserve fractional values; integer
// attachments or half-float substitutes do not have the same semantics.
static bool run_T7_norm16_roundtrip()
{
    CHECK(extSupported("GL_EXT_texture_norm16"), "GL_EXT_texture_norm16 available");
    static const char kWrite[] =
        "#version 310 es\nprecision highp float;\n"
        "layout(location = 0) out highp vec4 c;\n"
        "uniform highp vec4 encoded;\n"
        "void main() { c = encoded; }\n";
    static const char kSample[] =
        "#version 310 es\nprecision highp float;\n"
        "layout(location = 0) out highp vec4 c;\n"
        "uniform highp sampler2D tex;\n"
        "uniform highp vec4 expected;\n"
        "void main() { c = vec4(lessThanEqual(abs(texture(tex, vec2(0.5)) - expected), vec4(2.0 / 65535.0))); }\n";
    GLuint writer = makeProgram(kWrite);
    GLuint sampler = makeProgram(kSample);
    if (!writer || !sampler) {
        if (writer) glDeleteProgram(writer);
        if (sampler) glDeleteProgram(sampler);
        return false;
    }
    GLint savedViewport[4];
    glGetIntegerv(GL_VIEWPORT, savedViewport);
    glActiveTexture(GL_TEXTURE0);
    GLuint tex = makeTexture();
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, 0x805b /* GL_RGBA16_EXT */, 64, 64, 0,
                 GL_RGBA, GL_UNSIGNED_SHORT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    GLuint fbo = makeFramebuffer();
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    GLenum setupError = glGetError();
    bool ok = status == GL_FRAMEBUFFER_COMPLETE && setupError == GL_NONE;
    const GLfloat encoded[4] = {0.25f, 0.75f, 0.12345f, 0.6789f};
    uint8_t matches[4] = {0, 0, 0, 0};
    if (ok) {
        glViewport(0, 0, 64, 64);
        const GLfloat clear[4] = {0, 0, 0, 0};
        glClearBufferfv(GL_COLOR, 0, clear);
        glUseProgram(writer);
        glUniform4fv(glGetUniformLocation(writer, "encoded"), 1, encoded);
        glDrawTri();
        GLenum writeError = glGetError();
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(savedViewport[0], savedViewport[1], savedViewport[2], savedViewport[3]);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, tex);
        glUseProgram(sampler);
        glUniform1i(glGetUniformLocation(sampler, "tex"), 0);
        glUniform4fv(glGetUniformLocation(sampler, "expected"), 1, encoded);
        glDrawTri();
        glUseProgram(0);
        GLenum sampleError = glGetError();
        bool readOk = readCenterPixel(matches);
        ok = writeError == GL_NONE && sampleError == GL_NONE && readOk;
        for (uint8_t value : matches) ok = ok && value == 255;
        printf("    normalized RGBA16 sampled component matches: (%u, %u, %u, %u), expected all 255\n",
               matches[0], matches[1], matches[2], matches[3]);
        if (writeError || sampleError)
            printf("    normalized RGBA16 write error=0x%x sample error=0x%x\n", writeError, sampleError);
    } else {
        printf("    normalized RGBA16 setup: framebuffer=0x%x GL error=0x%x\n", status, setupError);
    }
    glUseProgram(0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(savedViewport[0], savedViewport[1], savedViewport[2], savedViewport[3]);
    freeFramebuffer(fbo);
    freeTexture(tex);
    glDeleteProgram(writer);
    glDeleteProgram(sampler);
    return ok;
}

// Isolate shader-read -> image-copy ordering with valid, normalized RGBA8 data.
// RENDER_TESTS_COPY_FINISH=0/1 selects one mode for separate validation logs;
// unset runs both. Readback follows the copy so it cannot hide an ordering error.
using CopyImageSubDataEXT = void (GL_APIENTRYP)(GLuint, GLenum, GLint, GLint, GLint, GLint,
                                              GLuint, GLenum, GLint, GLint, GLint, GLint,
                                              GLsizei, GLsizei, GLsizei);

static bool runCopySyncCase(CopyImageSubDataEXT copyImage, int width, int height, int layers,
                            bool finishBeforeCopy, bool firstImageBinding = false)
{
    const char *test = firstImageBinding ? "T9" : "T8";
    const bool array = layers > 1;
    const GLenum target = array ? GL_TEXTURE_2D_ARRAY : GL_TEXTURE_2D;
    printf("    %s BEGIN %dx%dx%d finishBeforeOperation=%d\n", test, width, height, layers, finishBeforeCopy);
    fflush(stdout);
    static const char kWrite[] =
        "#version 310 es\nprecision highp float;\nprecision highp int;\n"
        "layout(location=0) out vec4 c;\nuniform int layer;\n"
        "void main() { uvec2 p=uvec2(gl_FragCoord.xy); uint l=uint(layer);"
        "c=vec4(uvec4((p.x*13u+p.y*7u+l*17u+19u)%256u,"
        "(p.x*3u+p.y*23u+l*11u+41u)%256u,"
        "(p.x*29u+p.y*5u+l*31u+67u)%256u,255u))/255.0; }\n";
    const std::string sampleSource = std::string(
        "#version 310 es\nprecision highp float;\nprecision highp int;\n"
        "layout(location=0) out vec4 c;\nuniform highp ") +
        (array ? "sampler2DArray" : "sampler2D") + " tex;\nuniform int layer;\n"
        "void main() { c=texelFetch(tex, " +
        (array ? "ivec3(ivec2(gl_FragCoord.xy),layer)" : "ivec2(gl_FragCoord.xy)") +
        ",0); }\n";
    GLuint writer = makeProgram(kWrite);
    GLuint sample = makeProgram(sampleSource.c_str());
    if (!writer || !sample) {
        if (writer) glDeleteProgram(writer);
        if (sample) glDeleteProgram(sample);
        return false;
    }
    GLuint compute = 0;
    if (firstImageBinding) {
        const std::string coordinates = array ? "ivec3(gl_GlobalInvocationID)" : "ivec2(gl_GlobalInvocationID.xy)";
        const std::string imageType = array ? "image2DArray" : "image2D";
        const std::string computeSource = std::string(
            "#version 310 es\nprecision highp float;\nprecision highp int;\n"
            "layout(local_size_x=4,local_size_y=4,local_size_z=1) in;\n"
            "layout(binding=0,rgba8) readonly uniform highp ") + imageType + " srcImage;\n"
            "layout(binding=1,rgba8) writeonly uniform highp " + imageType + " dstImage;\n"
            "uniform ivec3 extent;\n"
            "void main() { if(any(greaterThanEqual(ivec3(gl_GlobalInvocationID),extent))) return;"
            "imageStore(dstImage," + coordinates + ",imageLoad(srcImage," + coordinates + ")); }\n";
        GLuint shader = compileShader(GL_COMPUTE_SHADER, computeSource.c_str());
        if (shader) {
            compute = glCreateProgram();
            glAttachShader(compute, shader);
            glLinkProgram(compute);
            glDeleteShader(shader);
            GLint linked = 0;
            glGetProgramiv(compute, GL_LINK_STATUS, &linked);
            if (!linked) {
                char log[8192];
                glGetProgramInfoLog(compute, sizeof(log), nullptr, log);
                printf("    T9 compute link error: %s\n", log);
                glDeleteProgram(compute);
                compute = 0;
            }
        }
        if (!compute) {
            glDeleteProgram(writer);
            glDeleteProgram(sample);
            return false;
        }
    }
    GLint savedViewport[4];
    glGetIntegerv(GL_VIEWPORT, savedViewport);
    GLuint source = makeTexture(), destination = makeTexture(), scratch = makeTexture();
    GLuint fbo = makeFramebuffer();
    glActiveTexture(GL_TEXTURE0);
    auto allocate = [&](GLuint texture, GLenum textureTarget) {
        glBindTexture(textureTarget, texture);
        // ES image units require immutable GL textures. ANGLE may still
        // recreate their backing Vulkan image when STORAGE usage is first needed.
        if (firstImageBinding && texture != scratch) {
            if (textureTarget == GL_TEXTURE_2D_ARRAY)
                glTexStorage3D(textureTarget, 1, GL_RGBA8, width, height, layers);
            else
                glTexStorage2D(textureTarget, 1, GL_RGBA8, width, height);
        } else         if (textureTarget == GL_TEXTURE_2D_ARRAY)
            glTexImage3D(textureTarget, 0, GL_RGBA8, width, height, layers, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        else
            glTexImage2D(textureTarget, 0, GL_RGBA8, width, height, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        glTexParameteri(textureTarget, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(textureTarget, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    };
    auto attach = [&](GLuint texture, GLenum textureTarget, int layer) {
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        if (textureTarget == GL_TEXTURE_2D_ARRAY)
            glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, texture, 0, layer);
        else
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, textureTarget, texture, 0);
        return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    };
    auto checkPixels = [&](int layer, const char *label) {
        std::vector<uint8_t> pixels(size_t(width) * height * 4, 0);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
        GLenum error = glGetError();
        if (error != GL_NONE) {
            printf("    T8 %s read error=0x%x\n", label, error);
            return false;
        }
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            const uint8_t expected[4] = {
                uint8_t((x*13+y*7+layer*17+19)%256),
                uint8_t((x*3+y*23+layer*11+41)%256),
                uint8_t((x*29+y*5+layer*31+67)%256), 255};
            for (int channel = 0; channel < 4; ++channel) {
                uint8_t actual = pixels[(size_t(y)*width+x)*4+channel];
                if (actual != expected[channel]) {
                    printf("    T8 %s mismatch layer=%d xy=%d,%d channel=%d actual=%u expected=%u\n",
                           label, layer, x, y, channel, actual, expected[channel]);
                    return false;
                }
            }
        }
        return true;
    };
    bool ok = [&]() {
        allocate(source, target);
        allocate(destination, target);
        allocate(scratch, GL_TEXTURE_2D);
        if (glGetError() != GL_NONE) return false;
        glViewport(0, 0, width, height);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);
        glDisable(GL_DITHER);
        glDisable(GL_SCISSOR_TEST);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glUseProgram(writer);
        for (int layer = 0; layer < layers; ++layer) {
            if (!attach(source, target, layer)) return false;
            glUniform1i(glGetUniformLocation(writer, "layer"), layer);
            glDrawTri();
        }
        if (!attach(scratch, GL_TEXTURE_2D, 0)) return false;
        glBindTexture(target, source);
        glUseProgram(sample);
        glUniform1i(glGetUniformLocation(sample, "tex"), 0);
        for (int layer = 0; layer < layers; ++layer) {
            glUniform1i(glGetUniformLocation(sample, "layer"), layer);
            glDrawTri();
        }
        glUseProgram(0);
        if (glGetError() != GL_NONE) return false;
        glFlush();
        if (finishBeforeCopy) glFinish();
        if (firstImageBinding) {
            glBindImageTexture(0, source, 0, array ? GL_TRUE : GL_FALSE, 0, GL_READ_ONLY, GL_RGBA8);
            glBindImageTexture(1, destination, 0, array ? GL_TRUE : GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8);
            glUseProgram(compute);
            glUniform3i(glGetUniformLocation(compute, "extent"), width, height, layers);
            glDispatchCompute((GLuint(width)+3)/4, (GLuint(height)+3)/4, GLuint(layers));
            glMemoryBarrier(GL_FRAMEBUFFER_BARRIER_BIT | GL_SHADER_IMAGE_ACCESS_BARRIER_BIT |
                            GL_TEXTURE_FETCH_BARRIER_BIT | GL_TEXTURE_UPDATE_BARRIER_BIT);
            glUseProgram(0);
        } else {
            copyImage(source, target, 0, 0, 0, 0, destination, target, 0, 0, 0, 0,
                      width, height, layers);
        }
        GLenum copyError = glGetError();
        if (copyError != GL_NONE) {
            printf("    %s operation error=0x%x\n", test, copyError);
            return false;
        }
        // Reads follow the operation under test. Scratch checks the last source
        // sample. Destination checks cover every pixel in every layer.
        if (!checkPixels(layers-1, "source sample")) return false;
        for (int layer = 0; layer < layers; ++layer)
            if (!attach(destination, target, layer) || !checkPixels(layer, "copied image")) return false;
        return true;
    }();
    glUseProgram(0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(target, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glViewport(savedViewport[0], savedViewport[1], savedViewport[2], savedViewport[3]);
    if (firstImageBinding) {
        glBindImageTexture(0, 0, 0, GL_FALSE, 0, GL_READ_ONLY, GL_RGBA8);
        glBindImageTexture(1, 0, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8);
        glDeleteProgram(compute);
    }
    freeFramebuffer(fbo);
    freeTexture(source); freeTexture(destination); freeTexture(scratch);
    glDeleteProgram(writer); glDeleteProgram(sample);
    printf("    %s END %dx%dx%d finishBeforeOperation=%d %s (%d pixels checked)\n",
           test, width, height, layers, finishBeforeCopy, ok ? "PASS" : "FAIL", width*height*layers);
    fflush(stdout);
    return ok;
}

static bool run_T8_copy_sync_roundtrip()
{
    CHECK(extSupported("GL_EXT_copy_image"), "GL_EXT_copy_image available");
    auto copyImage = reinterpret_cast<CopyImageSubDataEXT>(eglGetProcAddress("glCopyImageSubDataEXT"));
    CHECK(copyImage != nullptr, "resolve glCopyImageSubDataEXT");
    const char *mode = getenv("RENDER_TESTS_COPY_FINISH");
    bool ok = true;
    for (bool finish : {false, true}) {
        if (mode && finish != (strcmp(mode, "1") == 0)) continue;
        bool small = runCopySyncCase(copyImage, 1, 1, 1, finish);
        bool array = runCopySyncCase(copyImage, 23, 15, 32, finish);
        ok = small && array && ok;
    }
    return ok;
}

// Exercise first image binding after framebuffer writes and texture sampling.
// No image is bound for load/store until after the source rendering pass.
static bool run_T9_first_image_binding_roundtrip()
{
    const char *mode = getenv("RENDER_TESTS_COPY_FINISH");
    bool ok = true;
    for (bool finish : {false, true}) {
        if (mode && finish != (strcmp(mode, "1") == 0)) continue;
        bool small = runCopySyncCase(nullptr, 1, 1, 1, finish, true);
        bool array = runCopySyncCase(nullptr, 23, 15, 32, finish, true);
        ok = small && array && ok;
    }
    return ok;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

static bool runAllTests()
{
    TEST(run_T0_caps);
    TEST(run_T6_capability_dump);
    TEST(run_T2b_renderable_formats);
    TEST(run_T1_framebuffer_fetch);
    TEST(run_T2_uint_rgba16ui);
    TEST(run_T3_deferred_roundtrip);
    TEST(run_T4_fancy_sanity);
    TEST(run_T4b_readback_variants);
    TEST(run_T5_uint_rgba8ui);
    TEST(run_T7_norm16_roundtrip);
    TEST(run_T8_copy_sync_roundtrip);
    TEST(run_T9_first_image_binding_roundtrip);
    return gFailures == 0;
}

static bool setupEGL(const std::string &icdPath, EGLDisplay &dpy, EGLSurface &surf, EGLContext &ctx)
{
    setenv("ANGLE_DEFAULT_PLATFORM", "vulkan", 1);
    setenv("VK_ICD_FILENAMES", icdPath.c_str(), 1);

    dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    CHECK(dpy != EGL_NO_DISPLAY, "eglGetDisplay");
    EGLint major = 0, minor = 0;
    CHECK(eglInitialize(dpy, &major, &minor) == EGL_TRUE, "eglInitialize");
    printf("EGL %d.%d, ICD: %s\n", major, minor, icdPath.c_str());

    EGLint cfgAttrs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 16,
        EGL_NONE,
    };
    EGLConfig cfg;
    EGLint numConfigs = 0;
    CHECK(eglChooseConfig(dpy, cfgAttrs, &cfg, 1, &numConfigs) == EGL_TRUE && numConfigs > 0,
          "eglChooseConfig(pbuffer ES3)");

    EGLint pbAttrs[] = {EGL_WIDTH, 512, EGL_HEIGHT, 512, EGL_NONE};
    surf = eglCreatePbufferSurface(dpy, cfg, pbAttrs);
    CHECK(surf != EGL_NO_SURFACE, "eglCreatePbufferSurface");

    EGLint ctxAttrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxAttrs);
    CHECK(ctx != EGL_NO_CONTEXT, "eglCreateContext");
    CHECK(eglMakeCurrent(dpy, surf, surf, ctx) == EGL_TRUE, "eglMakeCurrent");

    glViewport(0, 0, 512, 512);
    gVao = makeFullscreenVAO();
    CHECK(gVao != 0, "create full-screen VAO");
    return true;
}

int main(int argc, char **argv)
{
    // ANGLE's macOS display needs Cocoa even without a window.
    @autoreleasepool {
        (void)[NSApplication sharedApplication];

        std::string icdPath;
        if (argc > 1) {
            icdPath = argv[1];
        } else {
            // Resolve relative to the executable: <root>/tools/render-tests/render-tests
            std::string self(argv[0]);
            size_t slash = self.find_last_of('/');
            std::string dir = (slash == std::string::npos) ? "." : self.substr(0, slash);
            icdPath = dir + "/../../out/moltenvk/MoltenVK_icd.json";
        }
        if (argc > 2) {
            gFilter = argv[2];
        }

        EGLDisplay dpy = EGL_NO_DISPLAY;
        EGLSurface surf = EGL_NO_SURFACE;
        EGLContext ctx = EGL_NO_CONTEXT;
        if (!setupEGL(icdPath, dpy, surf, ctx)) {
            return 1;
        }

        bool ok = runAllTests();
        printf("\n%s (%d failure%s)\n", ok ? "ALL TESTS PASSED" : "TESTS FAILED",
               gFailures, gFailures == 1 ? "" : "s");

        if (gVao) glDeleteVertexArrays(1, &gVao);
        eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroyContext(dpy, ctx);
        eglDestroySurface(dpy, surf);
        eglTerminate(dpy);
    }
    return gFailures == 0 ? 0 : 1;
}
