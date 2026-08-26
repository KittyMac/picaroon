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

static inline long picaroon_curl_redir_protocols(void) {
    return CURLPROTO_HTTP | CURLPROTO_HTTPS;
}

/// libcurl's version as a packed integer, 0xMMNNPP. corelibs formats its User-Agent
/// from the same numbers via CFURLSessionCurlVersionInfo().
static inline long picaroon_curl_version_num(void) {
    curl_version_info_data *info = curl_version_info(CURLVERSION_NOW);
    return info ? (long)info->version_num : 0;
}

/// Whether the headers we compiled against know CURLOPT_CAINFO_BLOB (libcurl 7.77+).
/// A 1 here does not guarantee the *runtime* libcurl supports it -- an older library
/// answers CURLE_UNKNOWN_OPTION (48) -- so callers must check the setopt result too.
// CURLOPT_CAINFO_BLOB is an *enumerator* in the CURLoption enum, not a #define, so
// `#if defined(CURLOPT_CAINFO_BLOB)` is always false and silently disables the whole
// blob path. Gate on the version macro instead: the option arrived in 7.77.0, and
// struct curl_blob in 7.71.0.
#define PICAROON_HAS_CAINFO_BLOB (LIBCURL_VERSION_NUM >= 0x074D00)

static inline int picaroon_curl_has_cainfo_blob(void) {
#if PICAROON_HAS_CAINFO_BLOB
    return 1;
#else
    return 0;
#endif
}

/// Supply the CA bundle as PEM bytes rather than a file path. CURL_BLOB_COPY makes
/// libcurl take its own copy, so the caller's buffer need not outlive the call.
static inline CURLcode picaroon_curl_setopt_cainfo_blob(CURL *handle, const void *bytes, size_t length) {
#if PICAROON_HAS_CAINFO_BLOB
    struct curl_blob blob;
    blob.data = (void *)bytes;
    blob.len = length;
    blob.flags = CURL_BLOB_COPY;
    return curl_easy_setopt(handle, CURLOPT_CAINFO_BLOB, &blob);
#else
    (void)handle; (void)bytes; (void)length;
    return CURLE_UNKNOWN_OPTION;
#endif
}

static inline CURLcode picaroon_curl_getinfo_double(CURL *handle, CURLINFO info, double *value) {
    return curl_easy_getinfo(handle, info, value);
}

static inline CURLcode picaroon_curl_getinfo_long(CURL *handle, CURLINFO info, long *value) {
    return curl_easy_getinfo(handle, info, value);
}

static inline CURLcode picaroon_curl_getinfo_str(CURL *handle, CURLINFO info, char **value) {
    return curl_easy_getinfo(handle, info, value);
}

#endif
