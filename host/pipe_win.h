// Windows named-pipe server for the JSON IPC, modelled on mpv's ipc-win.c.
// Pipes are opened overlapped: on a synchronous handle a blocked ReadFile in
// one thread would also block WriteFile from the event thread.
#ifndef VMPV_HOST_PIPE_WIN_H
#define VMPV_HOST_PIPE_WIN_H

#include <windows.h>

// Creates one instance of the pipe \\.\pipe\name. first fails if the name is
// already in use by another process. Returns NULL on error.
static HANDLE vh_pipe_create(const wchar_t *path, int first) {
    DWORD mode = PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED;
    if (first) mode |= FILE_FLAG_FIRST_PIPE_INSTANCE;
    HANDLE h = CreateNamedPipeW(path, mode, PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                                PIPE_UNLIMITED_INSTANCES, 4096, 4096, 0, NULL);
    return h == INVALID_HANDLE_VALUE ? NULL : h;
}

// Waits for and returns the result of an overlapped operation started on h.
static int vh_finish(HANDLE h, OVERLAPPED *ov, BOOL started, DWORD *n) {
    if (!started && GetLastError() != ERROR_IO_PENDING) return 0;
    return GetOverlappedResult(h, ov, n, TRUE) ? 1 : 0;
}

// Blocks until a client connects. Returns 1 on success.
static int vh_pipe_accept(HANDLE h) {
    OVERLAPPED ov = {0};
    ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    BOOL ok = ConnectNamedPipe(h, &ov);
    DWORD n = 0;
    int rc;
    if (ok || GetLastError() == ERROR_PIPE_CONNECTED) rc = 1;
    else rc = vh_finish(h, &ov, FALSE, &n);
    CloseHandle(ov.hEvent);
    return rc;
}

// Reads up to size bytes. Returns the count, or -1 on disconnect, error or cancel.
static int vh_pipe_read(HANDLE h, void *buf, int size) {
    OVERLAPPED ov = {0};
    ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    DWORD n = 0;
    BOOL ok = ReadFile(h, buf, (DWORD)size, &n, &ov);
    int rc = ok ? (int)n : (vh_finish(h, &ov, FALSE, &n) ? (int)n : -1);
    CloseHandle(ov.hEvent);
    return rc;
}

// Writes all size bytes. Returns 1 on success.
static int vh_pipe_write(HANDLE h, const void *buf, int size) {
    const char *p = buf;
    while (size > 0) {
        OVERLAPPED ov = {0};
        ov.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
        DWORD n = 0;
        BOOL ok = WriteFile(h, p, (DWORD)size, &n, &ov);
        int done = ok ? 1 : vh_finish(h, &ov, FALSE, &n);
        CloseHandle(ov.hEvent);
        if (!done || n == 0) return 0;
        p += n;
        size -= (int)n;
    }
    return 1;
}

// Makes a pending read on h fail, so the thread blocked in it can exit.
static void vh_pipe_cancel(HANDLE h) { CancelIoEx(h, NULL); }

// A copy of the stderr handle the parent passed in, made before main: a V
// program built with -subsystem windows reopens stderr to NUL on startup when
// it has no console, which closes the original handle.
static HANDLE vh_stderr = NULL;
__attribute__((constructor)) static void vh_save_stderr(void) {
    HANDLE h = GetStdHandle(STD_ERROR_HANDLE);
    if (h && h != INVALID_HANDLE_VALUE)
        DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), &vh_stderr, 0, FALSE,
                        DUPLICATE_SAME_ACCESS);
}

static void vh_stderr_write(const char *s, int len) {
    HANDLE h = vh_stderr;
    DWORD n;
    if (h && h != INVALID_HANDLE_VALUE) WriteFile(h, s, (DWORD)len, &n, NULL);
}

static void vh_pipe_close(HANDLE h) {
    FlushFileBuffers(h);
    DisconnectNamedPipe(h);
    CloseHandle(h);
}

#endif
