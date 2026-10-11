// bedrock-gplay: the launcher's Google Play helper.
//
//   bedrock-gplay login    --state DIR                      (oauth token on stdin)
//   bedrock-gplay latest   --state DIR                      (email, token on stdin)
//   bedrock-gplay download --state DIR --version-code N --out DIR   (same)
//
// Prints one result per line on stdout:
//   email <address>
//   token <saved Google token>       (login only; the launcher keeps it in Keychain)
//   version-code <n>
//   progress <name> <done> <total>
//   file <absolute path>
// Exit codes: 0 done, 2 bad arguments, 3 not signed in or token refused,
// 1 anything else. Errors go to stderr as "error auth <text>" or "error <text>".
// The state folder holds the device identity and short-lived service cookies.
// The long-lived Google token is never written to disk here.
#include <playapi/api.h>
#include <playapi/checkin.h>
#include <playapi/device_info.h>
#include <playapi/file_login_cache.h>
#include <playapi/login.h>
#include <playapi/util/http.h>

#include <curl/curl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

#include <chrono>
#include <filesystem>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "config.h"

using namespace playapi;

static const char* const APP = "com.mojang.minecraftpe";

namespace {

struct auth_error : std::runtime_error {
    using std::runtime_error::runtime_error;
};

// Google says no with an Error= field, which upstream reports as "Login
// error: ...". Anything else, such as no network, is not a refused token.
[[noreturn]] void rethrow_login(std::runtime_error const& e) {
    if (std::string(e.what()).rfind("Login error:", 0) == 0)
        throw auth_error(e.what());
    throw std::runtime_error(e.what());
}

[[noreturn]] void usage() {
    std::cerr << "usage: bedrock-gplay login --state DIR\n"
                 "       bedrock-gplay latest --state DIR\n"
                 "       bedrock-gplay download --state DIR --version-code N --out DIR\n";
    exit(2);
}

void line(const std::string& s) {
    std::cout << s << std::endl;
}

struct session {
    device_info device;
    device_config dev_state{"device.conf.state"};
    file_login_cache login_cache{"token_cache.conf"};
    login_api login{device, login_cache};
    api play{device};

    session() {
        {
            std::ofstream f("device.conf");
            f << "config.native_platforms = [\n    arm64-v8a\n]\n";
        }
        std::ifstream dev_file("device.conf");
        config dev_conf;
        dev_conf.load(dev_file);
        device.load(dev_conf);
        dev_state.load_device_info_data(device);
        device.generate_fields();
        dev_state.set_device_info_data(device);
        dev_state.save();
        login.set_checkin_data(dev_state.checkin_data);
    }

    void sign_in(const std::string& oauth_token) {
        try {
            login.perform_with_access_token(oauth_token)->call();
        } catch (std::runtime_error& e) {
            rethrow_login(e);
        }
        if (!login.has_token())
            throw auth_error("Google did not return a token");
    }

    void use_token(const std::string& email, const std::string& token) {
        if (token.empty())
            throw auth_error("not signed in");
        login.set_token(email, token);
        try {
            login.verify()->call();
        } catch (std::runtime_error& e) {
            rethrow_login(e);
        }
    }

    // Registers the device and accepts the Play terms when Google asks.
    void connect() {
        if (dev_state.checkin_data.android_id == 0) {
            checkin_api checkin(device);
            checkin.add_auth(login)->call();
            dev_state.checkin_data = checkin.perform_checkin()->call();
            dev_state.save();
        }
        play.set_auth(login)->call();
        play.set_checkin_data(dev_state.checkin_data);
        dev_state.load_api_data(login.get_email(), play);
        if (!play.toc_cookie.empty() && !play.device_config_token.empty())
            return;
        play.fetch_user_settings()->call();
        auto toc = play.fetch_toc()->call();
        if (toc.payload().tocresponse().has_cookie())
            play.toc_cookie = toc.payload().tocresponse().cookie();
        if (toc.payload().tocresponse().requiresuploaddeviceconfig()) {
            auto resp = play.upload_device_config()->call();
            play.device_config_token = resp.payload().uploaddeviceconfigresponse().uploaddeviceconfigtoken();
            toc = play.fetch_toc()->call();
            if (toc.payload().tocresponse().has_cookie())
                play.toc_cookie = toc.payload().tocresponse().cookie();
        }
        if (toc.payload().tocresponse().has_tostoken())
            play.accept_tos(toc.payload().tocresponse().tostoken(), false)->call();
        dev_state.set_api_data(login.get_email(), play);
        dev_state.save();
    }
};

void inflate_into(z_stream& zs, FILE* f, char* data, size_t size, int flush) {
    char buf[64 * 1024];
    zs.next_in = (Bytef*) data;
    zs.avail_in = (uInt) size;
    do {
        zs.next_out = (Bytef*) buf;
        zs.avail_out = sizeof(buf);
        int ret = inflate(&zs, flush);
        if (ret != Z_OK && ret != Z_STREAM_END && ret != Z_BUF_ERROR)
            throw std::runtime_error("bad compressed download");
        fwrite(buf, 1, sizeof(buf) - zs.avail_out, f);
    } while (zs.avail_out == 0);
}

template <typename T>
void download_part(session& s, T const& dd, proto::finsky::HttpCookie const& cookie, std::string const& name,
                   std::string const& out_dir) {
    bool gzipped = dd.has_gzippeddownloadurl();
    http_request req(gzipped ? dd.gzippeddownloadurl() : dd.downloadurl());
    req.add_header("Accept-Encoding", "identity");
    req.add_header("Cookie", cookie.name() + "=" + cookie.value());
    req.set_user_agent("AndroidDownloadManager/" + s.device.build_version_string + " (Linux; U; Android " +
                       s.device.build_version_string + "; " + s.device.build_model + " Build/" +
                       s.device.build_id + ")");
    req.set_follow_location(true);
    req.set_timeout(0L);
    if (gzipped)
        req.set_encoding("gzip,deflate");

    std::string path = out_dir + "/" + name;
    std::string partial = path + ".partial";
    FILE* f = fopen(partial.c_str(), "wb");
    if (!f)
        throw std::runtime_error("cannot write " + partial);
    z_stream zs{};
    if (gzipped && inflateInit2(&zs, 31) != Z_OK)
        throw std::runtime_error("zlib init failed");
    req.set_custom_output_func([&](char* data, size_t size) {
        if (gzipped)
            inflate_into(zs, f, data, size, Z_NO_FLUSH);
        else if (fwrite(data, 1, size, f) != size)
            return (size_t) 0;
        return size;
    });
    auto last = std::chrono::steady_clock::now() - std::chrono::seconds(1);
    req.set_progress_callback([&](curl_off_t total, curl_off_t now, curl_off_t, curl_off_t) {
        auto t = std::chrono::steady_clock::now();
        if (total > 0 && (t - last >= std::chrono::milliseconds(250) || now == total)) {
            last = t;
            line("progress " + name + " " + std::to_string(now) + " " + std::to_string(total));
        }
    });
    auto resp = req.perform();
    if (gzipped) {
        inflate_into(zs, f, nullptr, 0, Z_FINISH);
        inflateEnd(&zs);
    }
    bool write_ok = fclose(f) == 0;
    if (!resp || resp.get_status_code() != 200 || !write_ok) {
        unlink(partial.c_str());
        throw std::runtime_error("download of " + name + " failed (HTTP " +
                                 std::to_string(resp.get_status_code()) + ")");
    }
    if (rename(partial.c_str(), path.c_str()) != 0)
        throw std::runtime_error("cannot write " + path);
    line("file " + path);
}

int run(int argc, char** argv) {
    if (argc < 2)
        usage();
    std::string cmd = argv[1];
    std::string state, out;
    long long version_code = -1;
    for (int i = 2; i < argc; i++) {
        std::string k = argv[i];
        if (i + 1 >= argc)
            usage();
        std::string v = argv[++i];
        if (k == "--state")
            state = v;
        else if (k == "--out")
            out = v;
        else if (k == "--version-code")
            version_code = std::atoll(v.c_str());
        else
            usage();
    }
    if (state.empty() || (cmd != "login" && cmd != "latest" && cmd != "download"))
        usage();
    if (cmd == "download" && (out.empty() || version_code <= 0))
        usage();

    umask(077);
    if (cmd == "download") {
        std::error_code ec;
        std::filesystem::create_directories(out, ec);
        char buf[PATH_MAX];
        if (!realpath(out.c_str(), buf))
            throw std::runtime_error("cannot open " + out);
        out = buf;
    }
    std::error_code ec;
    std::filesystem::create_directories(state, ec);
    if (chdir(state.c_str()) != 0)
        throw std::runtime_error("cannot open " + state);

    session s;
    if (cmd == "login") {
        std::string token;
        std::getline(std::cin, token);
        if (token.empty())
            throw auth_error("no token on stdin");
        s.sign_in(token);
        s.connect();
        line("email " + s.login.get_email());
        line("token " + s.login.get_token());
        return 0;
    }

    std::string email, token;
    std::getline(std::cin, email);
    std::getline(std::cin, token);
    s.use_token(email, token);
    s.connect();
    if (cmd == "latest") {
        auto details = s.play.details(APP)->call().payload().detailsresponse().docv2();
        if (!details.details().appdetails().has_versioncode())
            throw std::runtime_error("Google Play returned no version code");
        line("version-code " + std::to_string(details.details().appdetails().versioncode()));
        return 0;
    }

    auto resp = s.play.delivery(APP, (int) version_code, std::string())->call();
    if (!resp.payload().has_deliveryresponse() || !resp.payload().deliveryresponse().has_appdeliverydata())
        throw std::runtime_error("Google Play did not offer version " + std::to_string(version_code));
    auto dd = resp.payload().deliveryresponse().appdeliverydata();
    if (dd.downloadauthcookie_size() == 0)
        throw std::runtime_error("Google Play did not offer version " + std::to_string(version_code));
    download_part(s, dd, dd.downloadauthcookie(0), "base.apk", out);
    for (auto&& split : dd.splitdeliverydata())
        download_part(s, split, dd.downloadauthcookie(0), "split_" + split.id() + ".apk", out);
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    curl_global_init(CURL_GLOBAL_ALL);
    int code;
    try {
        code = run(argc, argv);
    } catch (auth_error& e) {
        std::cerr << "error auth " << e.what() << std::endl;
        code = 3;
    } catch (std::exception& e) {
        std::cerr << "error " << e.what() << std::endl;
        code = 1;
    }
    curl_global_cleanup();
    return code;
}
