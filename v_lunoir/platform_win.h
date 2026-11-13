#ifndef LUNOIR_PLATFORM_WIN_H
#define LUNOIR_PLATFORM_WIN_H
#define COBJMACROS
#include <windows.h>
#include <commdlg.h>
#include <shlobj.h>
#include <winhttp.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static char *lv_utf8(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    char *s = (char *)calloc(n > 0 ? n : 1, 1);
    if (n) WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL);
    return s;
}

static int lv_replace(const wchar_t *from, const wchar_t *to) {
    return MoveFileExW(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
}

static char *lv_locale(void) {
    wchar_t name[85] = {0};
    LCIDToLocaleName(GetUserDefaultUILanguage(), name, 85, 0);
    return lv_utf8(name);
}

static char *lv_pictures(void) {
    wchar_t path[MAX_PATH] = {0};
    SHGetFolderPathW(NULL, CSIDL_MYPICTURES, NULL, 0, path);
    return lv_utf8(path);
}

static char *lv_decode_text(const char *input, int length, unsigned int codepage) {
    int count = 0; wchar_t *wide = NULL;
    if (codepage == 1200 || codepage == 1201) {
        count = length / 2; wide = (wchar_t *)calloc(count + 1, sizeof(wchar_t));
        for (int i = 0; i < count; i++) wide[i] = codepage == 1200 ? (unsigned char)input[i * 2] | ((unsigned char)input[i * 2 + 1] << 8) : ((unsigned char)input[i * 2] << 8) | (unsigned char)input[i * 2 + 1];
    } else {
        count = MultiByteToWideChar(codepage, 0, input, length, NULL, 0);
        wide = (wchar_t *)calloc(count + 1, sizeof(wchar_t));
        if (count) MultiByteToWideChar(codepage, 0, input, length, wide, count);
    }
    char *result = lv_utf8(wide); free(wide); return result;
}

static void *lv_job(void) {
    HANDLE job = CreateJobObjectW(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {0};
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof(info))) {
        if (job) CloseHandle(job);
        return NULL;
    }
    return job;
}

typedef struct { HANDLE handle; DWORD pid; } LunoirProcess;
static LunoirProcess *lv_start(const wchar_t *cmd, const wchar_t *cwd, const wchar_t *out, const wchar_t *err, HANDLE job) {
    SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
    HANDLE input = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
    HANDLE output = CreateFileW(out && *out ? out : L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, CREATE_ALWAYS, 0, NULL);
    HANDLE errors = CreateFileW(err && *err ? err : L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, CREATE_ALWAYS, 0, NULL);
    STARTUPINFOW startup = {0}; PROCESS_INFORMATION info = {0};
    startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = input; startup.hStdOutput = output; startup.hStdError = errors;
    wchar_t *command = _wcsdup(cmd);
    BOOL ok = CreateProcessW(NULL, command, NULL, NULL, TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, NULL, cwd && *cwd ? cwd : NULL, &startup, &info);
    free(command); CloseHandle(input); CloseHandle(output); CloseHandle(errors);
    if (!ok) return NULL;
    if (job && !AssignProcessToJobObject(job, info.hProcess)) {
        TerminateProcess(info.hProcess, 1); CloseHandle(info.hThread); CloseHandle(info.hProcess); return NULL;
    }
    ResumeThread(info.hThread); CloseHandle(info.hThread);
    LunoirProcess *p = (LunoirProcess *)calloc(1, sizeof(*p)); p->handle = info.hProcess; p->pid = info.dwProcessId;
    return p;
}
static int lv_process_wait(LunoirProcess *p, DWORD timeout) { return p && WaitForSingleObject(p->handle, timeout) == WAIT_OBJECT_0; }
static int lv_process_exit(LunoirProcess *p) { DWORD code = 0; if (!p || !GetExitCodeProcess(p->handle, &code)) return -1; return (int)code; }
static void lv_process_close(LunoirProcess *p, int kill) {
    if (!p) return;
    if (kill && WaitForSingleObject(p->handle, 0) != WAIT_OBJECT_0) { TerminateProcess(p->handle, 1); WaitForSingleObject(p->handle, 3000); }
    CloseHandle(p->handle); free(p);
}

typedef struct { char *data; int len; int status; char *url; char *content_type; } LunoirHttp;
static LunoirHttp lv_fetch(const wchar_t *address, const wchar_t *agent) {
    LunoirHttp result = {0};
    URL_COMPONENTSW parts = {0}; parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength = (DWORD)-1;
    if (!WinHttpCrackUrl(address, 0, 0, &parts)) return result;
    wchar_t *host = (wchar_t *)calloc(parts.dwHostNameLength + 1, sizeof(wchar_t));
    wcsncpy(host, parts.lpszHostName, parts.dwHostNameLength);
    size_t path_len = parts.dwUrlPathLength + parts.dwExtraInfoLength;
    wchar_t *path = (wchar_t *)calloc(path_len + 2, sizeof(wchar_t));
    if (parts.dwUrlPathLength) wcsncpy(path, parts.lpszUrlPath, parts.dwUrlPathLength); else wcscpy(path, L"/");
    if (parts.dwExtraInfoLength) wcsncat(path, parts.lpszExtraInfo, parts.dwExtraInfoLength);
    HINTERNET session = WinHttpOpen(agent, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, NULL, NULL, 0);
    HINTERNET connection = NULL, request = NULL;
    if (!session) goto cleanup;
    WinHttpSetTimeouts(session, 15000, 15000, 60000, 60000);
    connection = WinHttpConnect(session, host, parts.nPort, 0); if (!connection) goto cleanup;
    request = WinHttpOpenRequest(connection, L"GET", path, NULL, NULL, WINHTTP_DEFAULT_ACCEPT_TYPES, parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0);
    if (!request) goto cleanup;
    DWORD decompress = WINHTTP_DECOMPRESSION_FLAG_GZIP | WINHTTP_DECOMPRESSION_FLAG_DEFLATE;
    WinHttpSetOption(request, WINHTTP_OPTION_DECOMPRESSION, &decompress, sizeof(decompress));
    if (!WinHttpSendRequest(request, NULL, 0, NULL, 0, 0, 0) || !WinHttpReceiveResponse(request, NULL)) goto cleanup;
    DWORD size = sizeof(DWORD), status = 0;
    WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, NULL, &status, &size, NULL); result.status = (int)status;
    size = 0; WinHttpQueryOption(request, WINHTTP_OPTION_URL, NULL, &size);
    if (size) { wchar_t *s = (wchar_t *)calloc(size + 2, 1); if (WinHttpQueryOption(request, WINHTTP_OPTION_URL, s, &size)) result.url = lv_utf8(s); free(s); }
    size = 0; WinHttpQueryHeaders(request, WINHTTP_QUERY_CONTENT_TYPE, NULL, NULL, &size, NULL);
    if (size) { wchar_t *s = (wchar_t *)calloc(size + 2, 1); if (WinHttpQueryHeaders(request, WINHTTP_QUERY_CONTENT_TYPE, NULL, s, &size, NULL)) result.content_type = lv_utf8(s); free(s); }
    size_t used = 0, capacity = 65536; result.data = (char *)malloc(capacity + 1);
    for (;;) {
        DWORD received = 0; char chunk[65536];
        if (!WinHttpReadData(request, chunk, sizeof(chunk), &received)) { free(result.data); result.data = NULL; result.status = 0; break; }
        if (!received) break;
        if (used + received > 256 * 1024 * 1024) { free(result.data); result.data = NULL; result.status = 0; break; }
        if (used + received > capacity) { capacity = (used + received) * 2; char *next = (char *)realloc(result.data, capacity + 1); if (!next) { free(result.data); result.data = NULL; result.status = 0; break; } result.data = next; }
        memcpy(result.data + used, chunk, received); used += received;
    }
    if (result.data) { result.data[used] = 0; result.len = (int)used; }
cleanup:
    if (request) WinHttpCloseHandle(request); if (connection) WinHttpCloseHandle(connection); if (session) WinHttpCloseHandle(session);
    free(host); free(path); return result;
}
static void lv_http_free(LunoirHttp *r) { free(r->data); free(r->url); free(r->content_type); }

static void *lv_find_window(const wchar_t *title) { return FindWindowW(NULL, title); }
static void *lv_video_create(HWND parent) { return CreateWindowExW(0, L"STATIC", L"Lunoir V video", WS_CHILD | WS_DISABLED | SS_BLACKRECT, 0, 0, 1, 1, parent, NULL, NULL, NULL); }
static void lv_client(HWND parent, int *out) { RECT r = {0}; GetClientRect(parent, &r); out[0] = r.left; out[1] = r.top; out[2] = r.right; out[3] = r.bottom; }
static void lv_bounds(HWND parent, int *out) { RECT r = {0}; GetWindowRect(parent, &r); out[0] = r.left; out[1] = r.top; out[2] = r.right; out[3] = r.bottom; }
static void lv_position(HWND hwnd, int x, int y, int w, int h) { SetWindowPos(hwnd, HWND_TOP, x, y, w, h, SWP_NOACTIVATE); }
static void lv_region(HWND hwnd, int w, int h, int radius, const int *holes, int count) {
    if (!radius && !count) { SetWindowRgn(hwnd, NULL, TRUE); return; }
    HRGN region = radius ? CreateRoundRectRgn(0, 0, w + 1, h + 1, radius * 2, radius * 2) : CreateRectRgn(0, 0, w, h);
    for (int i = 0; i < count; i++) { const int *p = holes + i * 5; HRGN hole = CreateRoundRectRgn(p[0], p[1], p[0] + p[2] + 1, p[1] + p[3] + 1, p[4] * 2, p[4] * 2); CombineRgn(region, region, hole, RGN_DIFF); DeleteObject(hole); }
    if (!SetWindowRgn(hwnd, region, TRUE)) DeleteObject(region);
}
static int lv_cursor(HWND parent, HWND video, int *out) {
    POINT p; if (!GetCursorPos(&p)) return 0;
    HWND under = WindowFromPoint(p); if (under != parent && under != video && !IsChild(parent, under)) return 0;
    ScreenToClient(parent, &p); out[0] = p.x; out[1] = p.y; return 1;
}
static int lv_focused(HWND hwnd) { return GetForegroundWindow() == hwnd; }
static int lv_key(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
static void lv_show(HWND hwnd, int show) { ShowWindow(hwnd, show ? SW_SHOWNA : SW_HIDE); }
static void lv_raise(HWND hwnd) { SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE); }
static void lv_destroy(HWND hwnd) { if (IsWindow(hwnd)) DestroyWindow(hwnd); }
static void lv_focus(HWND hwnd) { AllowSetForegroundWindow(ASFW_ANY); if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd); }
static void lv_pump(void) { MSG msg; while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); } }

static char *lv_open_dialog(HWND parent, int folder, int multiple, const wchar_t *filter) {
    if (folder) {
        BROWSEINFOW options = {0}; wchar_t display[MAX_PATH] = {0}, path[MAX_PATH] = {0};
        options.hwndOwner = parent; options.pszDisplayName = display; options.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
        CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
        PIDLIST_ABSOLUTE item = SHBrowseForFolderW(&options);
        if (item) { SHGetPathFromIDListW(item, path); CoTaskMemFree(item); }
        CoUninitialize(); return lv_utf8(path);
    }
    wchar_t *buffer = (wchar_t *)calloc(65536, sizeof(wchar_t)); OPENFILENAMEW options = {0};
    options.lStructSize = sizeof(options); options.hwndOwner = parent; options.lpstrFile = buffer; options.nMaxFile = 65536;
    options.lpstrFilter = filter; options.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR | (multiple ? OFN_ALLOWMULTISELECT : 0);
    if (!GetOpenFileNameW(&options)) { free(buffer); return (char *)calloc(1, 1); }
    // Return UTF-8 lines, retaining the directory as the first line for a multi-selection.
    size_t used = 0; char *result = (char *)calloc(262144, 1);
    for (wchar_t *p = buffer; *p; p += wcslen(p) + 1) { char *s = lv_utf8(p); size_t n = strlen(s); if (used + n + 2 < 262144) { memcpy(result + used, s, n); used += n; result[used++] = '\n'; } free(s); }
    free(buffer); return result;
}
typedef struct {
    HANDLE mutex, thread, pipe;
    wchar_t *name;
    HWND hwnd;
    LONG closing;
    int claimed;
    CRITICAL_SECTION lock;
    char *pending;
} LunoirInstance;
static DWORD WINAPI lv_instance_thread(void *context) {
    LunoirInstance *s = (LunoirInstance *)context;
    while (!InterlockedCompareExchange(&s->closing, 0, 0)) {
        HANDLE pipe = CreateNamedPipeW(s->name, PIPE_ACCESS_DUPLEX, PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT, PIPE_UNLIMITED_INSTANCES, 4096, 65536, 0, NULL);
        if (pipe == INVALID_HANDLE_VALUE) break;
        s->pipe = pipe;
        if (ConnectNamedPipe(pipe, NULL) || GetLastError() == ERROR_PIPE_CONNECTED) {
            char input[65537]; DWORD count = 0;
            if (ReadFile(pipe, input, 65536, &count, NULL) && count) {
                input[count] = 0;
                EnterCriticalSection(&s->lock);
                size_t old = s->pending ? strlen(s->pending) : 0;
                char *next = (char *)realloc(s->pending, old + count + 2);
                if (next) { s->pending = next; memcpy(next + old, input, count); next[old + count] = '\n'; next[old + count + 1] = 0; }
                LeaveCriticalSection(&s->lock);
                char reply[64]; int n = snprintf(reply, sizeof(reply), "%llu", (unsigned long long)(uintptr_t)s->hwnd);
                WriteFile(pipe, reply, n, &count, NULL);
            }
        }
        DisconnectNamedPipe(pipe); CloseHandle(pipe); s->pipe = NULL;
    }
    return 0;
}
static LunoirInstance *lv_instance_create(const wchar_t *mutex_name, const wchar_t *pipe_name) {
    LunoirInstance *s = (LunoirInstance *)calloc(1, sizeof(*s));
    s->mutex = CreateMutexW(NULL, FALSE, mutex_name);
    s->claimed = s->mutex && GetLastError() != ERROR_ALREADY_EXISTS;
    s->name = _wcsdup(pipe_name); InitializeCriticalSection(&s->lock); return s;
}
static int lv_instance_claimed(LunoirInstance *s) { return s && s->claimed; }
static void lv_instance_serve(LunoirInstance *s, HWND hwnd) {
    if (!s || !s->claimed || s->thread) return;
    s->hwnd = hwnd; s->thread = CreateThread(NULL, 0, lv_instance_thread, s, 0, NULL);
}
static char *lv_instance_take(LunoirInstance *s) {
    if (!s) return NULL;
    EnterCriticalSection(&s->lock); char *result = s->pending; s->pending = NULL; LeaveCriticalSection(&s->lock); return result;
}
static int lv_instance_io(HANDLE h, int write, void *data, DWORD length, DWORD *done) {
    OVERLAPPED ov = {0}; ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    BOOL ok = write ? WriteFile(h, data, length, done, &ov) : ReadFile(h, data, length, done, &ov);
    if (!ok && GetLastError() == ERROR_IO_PENDING) {
        if (WaitForSingleObject(ov.hEvent, 2000) != WAIT_OBJECT_0) { CancelIoEx(h, &ov); GetOverlappedResult(h, &ov, done, TRUE); ok = FALSE; }
        else ok = GetOverlappedResult(h, &ov, done, TRUE);
    }
    CloseHandle(ov.hEvent); return ok;
}
static int lv_instance_forward(LunoirInstance *s, const char *message, int timeout) {
    ULONGLONG until = GetTickCount64() + timeout;
    AllowSetForegroundWindow(ASFW_ANY);
    do {
        HANDLE h = CreateFileW(s->name, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
        if (h != INVALID_HANDLE_VALUE) {
            DWORD mode = PIPE_READMODE_MESSAGE, n = 0; SetNamedPipeHandleState(h, &mode, NULL, NULL);
            char reply[65] = {0}; int ok = lv_instance_io(h, 1, (void *)message, (DWORD)strlen(message), &n) && lv_instance_io(h, 0, reply, 64, &n);
            CloseHandle(h);
            if (ok) { lv_focus((HWND)(uintptr_t)_strtoui64(reply, NULL, 10)); return 1; }
        }
        Sleep(100);
    } while (GetTickCount64() < until);
    return 0;
}
static void lv_instance_close(LunoirInstance *s) {
    if (!s) return;
    InterlockedExchange(&s->closing, 1);
    if (s->thread) { CancelSynchronousIo(s->thread); if (WaitForSingleObject(s->thread, 3000) != WAIT_OBJECT_0) return; CloseHandle(s->thread); }
    if (s->mutex) CloseHandle(s->mutex);
    DeleteCriticalSection(&s->lock); free(s->name); free(s->pending); free(s);
}
#endif
