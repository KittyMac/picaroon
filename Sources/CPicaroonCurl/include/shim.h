#ifndef PICAROON_CURL_SHIM_H
#define PICAROON_CURL_SHIM_H

// curl_easy_setopt and curl_easy_getinfo are variadic, and Swift cannot call
// variadic C functions. These typed wrappers are the same approach that
// swift-corelibs-foundation uses in CFURLSessionInterface.c.

#include <curl/curl.h>

typedef size_t (*picaroon_curl_write_cb)(char *buffer, size_t size, size_t nitems, void *userdata);
typedef int (*picaroon_curl_xferinfo_cb)(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow);

static inline CURLcode picaroon_curl_global_init(void) {
    return curl_global_init(CURL_GLOBAL_SSL);
}

static inline long picaroon_curl_error_size(void) {
    return CURL_ERROR_SIZE;
}

static inline CURLcode picaroon_curl_setopt_long(CURL *handle, CURLoption option, long value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode picaroon_curl_setopt_str(CURL *handle, CURLoption option, const char *value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode picaroon_curl_setopt_ptr(CURL *handle, CURLoption option, void *value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode picaroon_curl_setopt_off(CURL *handle, CURLoption option, curl_off_t value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode picaroon_curl_setopt_write(CURL *handle, CURLoption option, picaroon_curl_write_cb value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode picaroon_curl_setopt_xferinfo(CURL *handle, CURLoption option, picaroon_curl_xferinfo_cb value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode picaroon_curl_getinfo_long(CURL *handle, CURLINFO info, long *value) {
    return curl_easy_getinfo(handle, info, value);
}

static inline CURLcode picaroon_curl_getinfo_str(CURL *handle, CURLINFO info, char **value) {
    return curl_easy_getinfo(handle, info, value);
}

#endif
