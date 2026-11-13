#ifndef LUNOIR_DROP_WIN_H
#define LUNOIR_DROP_WIN_H
#include "platform_win.h"
#include <oleidl.h>
#include <shellapi.h>
#include <math.h>

typedef struct {
    IDropTarget target;
    LONG refs;
    HWND parent, hwnd;
    HANDLE thread, ready;
    CRITICAL_SECTION lock;
    char *pending;
    int hint, shown, was_down, press_outside;
    int last_x, last_y, last_w, last_h, last_hint;
} LunoirDrop;

static void lv_drop_append(char **result, const wchar_t *path) {
    char *text = lv_utf8(path);
    size_t old = *result ? strlen(*result) : 0, size = strlen(text);
    char *next = (char *)realloc(*result, old + size + 2);
    if (next) { *result = next; memcpy(next + old, text, size); next[old + size] = '\n'; next[old + size + 1] = 0; }
    free(text);
}

static char *lv_drop_data(IDataObject *data) {
    FORMATETC format = {CF_HDROP, NULL, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    STGMEDIUM medium = {0}; char *result = NULL;
    if (SUCCEEDED(IDataObject_GetData(data, &format, &medium))) {
        UINT count = DragQueryFileW((HDROP)medium.hGlobal, 0xffffffff, NULL, 0);
        for (UINT i = 0; i < count; i++) {
            UINT len = DragQueryFileW((HDROP)medium.hGlobal, i, NULL, 0);
            wchar_t *path = (wchar_t *)calloc(len + 1, sizeof(wchar_t));
            if (DragQueryFileW((HDROP)medium.hGlobal, i, path, len + 1)) lv_drop_append(&result, path);
            free(path);
        }
        ReleaseStgMedium(&medium);
        if (result) return result;
    }
    UINT formats[] = {CF_UNICODETEXT, RegisterClipboardFormatW(L"UniformResourceLocatorW")};
    for (int i = 0; i < 2; i++) {
        format.cfFormat = (CLIPFORMAT)formats[i]; memset(&medium, 0, sizeof(medium));
        if (FAILED(IDataObject_GetData(data, &format, &medium))) continue;
        const wchar_t *input = (const wchar_t *)GlobalLock(medium.hGlobal);
        if (input) {
            size_t limit = GlobalSize(medium.hGlobal) / sizeof(wchar_t);
            wchar_t *text = (wchar_t *)calloc(limit + 1, sizeof(wchar_t)); wcsncpy(text, input, limit);
            wchar_t *line = text;
            while (*line) {
                while (*line == L'\r' || *line == L'\n' || *line == L' ' || *line == L'\t') line++;
                wchar_t *end = line; while (*end && *end != L'\r' && *end != L'\n') end++;
                wchar_t saved = *end; *end = 0;
                if (!_wcsnicmp(line, L"http://", 7) || !_wcsnicmp(line, L"https://", 8)) {
                    size_t n = wcslen(line); while (n && (line[n - 1] == L' ' || line[n - 1] == L'\t')) line[--n] = 0;
                    lv_drop_append(&result, line); break;
                }
                if (!saved) break;
                line = end + 1;
            }
            free(text); GlobalUnlock(medium.hGlobal);
        }
        ReleaseStgMedium(&medium);
        if (result) return result;
    }
    return NULL;
}

static void lv_drop_paint(LunoirDrop *s) {
    RECT r; if (!GetClientRect(s->parent, &r)) return;
    int w = r.right, h = r.bottom; POINT position = {0, 0}; ClientToScreen(s->parent, &position);
    if (w <= 0 || h <= 0 || w > 20000 || h > 20000) return;
    if (s->last_x == position.x && s->last_y == position.y && s->last_w == w && s->last_h == h && s->last_hint == s->hint) return;
    HDC screen = GetDC(NULL), memory = CreateCompatibleDC(screen);
    BITMAPINFO info = {0}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth = w; info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    uint32_t *pixels = NULL; HBITMAP bitmap = CreateDIBSection(memory, &info, DIB_RGB_COLORS, (void **)&pixels, NULL, 0);
    if (bitmap) {
        for (size_t i = 0; i < (size_t)w * h; i++) pixels[i] = 0x01000000;
        if (s->hint) {
            double scale = GetDpiForWindow(s->parent) / 96.0; if (scale <= 0) scale = 1;
            int inset = (int)round(14 * scale), line = (int)round(2 * scale), radius = (int)round(18 * scale);
            if (line < 1) line = 1;
            int left = inset, top = inset, right = w - inset, bottom = h - inset;
            if (right - left >= radius * 2 && bottom - top >= radius * 2) {
                for (int y = top; y < bottom; y++) {
                    int dy = y < top + radius ? top + radius - y : y >= bottom - radius ? y - (bottom - radius - 1) : 0;
                    for (int x = left; x < right; x++) {
                        int corner = dy > 0 && (x < left + radius || x >= right - radius);
                        if (corner) {
                            int cx = x < left + radius ? left + radius : right - radius - 1;
                            double distance = hypot((double)x - cx, dy);
                            if (distance <= radius) pixels[(size_t)y * w + x] = distance > radius - line ? 0xbf5c6abf : 0x17090a17;
                        } else {
                            int border = (y < top + line || y >= bottom - line) ? ((x - left - radius) / (3 * line)) % 2 == 0 :
                                (x < left + line || x >= right - line) && ((y - top - radius) / (3 * line)) % 2 == 0;
                            pixels[(size_t)y * w + x] = border ? 0xbf5c6abf : 0x17090a17;
                        }
                    }
                }
            }
        }
        HGDIOBJ previous = SelectObject(memory, bitmap); POINT origin = {0, 0}; SIZE size = {w, h}; BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
        if (UpdateLayeredWindow(s->hwnd, screen, &position, &size, memory, &origin, 0, &blend, ULW_ALPHA)) {
            s->last_x = position.x; s->last_y = position.y; s->last_w = w; s->last_h = h; s->last_hint = s->hint;
        }
        SelectObject(memory, previous); DeleteObject(bitmap);
    }
    DeleteDC(memory); ReleaseDC(NULL, screen);
}

static HRESULT STDMETHODCALLTYPE lv_drop_query(IDropTarget *self, REFIID iid, void **out) {
    if (!out) return E_POINTER;
    if (IsEqualIID(iid, &IID_IUnknown) || IsEqualIID(iid, &IID_IDropTarget)) { *out = self; InterlockedIncrement(&((LunoirDrop *)self)->refs); return S_OK; }
    *out = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE lv_drop_addref(IDropTarget *self) { return InterlockedIncrement(&((LunoirDrop *)self)->refs); }
static ULONG STDMETHODCALLTYPE lv_drop_release(IDropTarget *self) { return InterlockedDecrement(&((LunoirDrop *)self)->refs); }
static DWORD lv_drop_effect(DWORD allowed) { return allowed & DROPEFFECT_COPY ? DROPEFFECT_COPY : allowed & DROPEFFECT_LINK; }
static HRESULT STDMETHODCALLTYPE lv_drop_enter(IDropTarget *self, IDataObject *data, DWORD keys, POINTL point, DWORD *effect) {
    LunoirDrop *s = (LunoirDrop *)self; char *items = lv_drop_data(data);
    *effect = items ? lv_drop_effect(*effect) : DROPEFFECT_NONE; free(items);
    s->hint = *effect != 0; lv_drop_paint(s); return S_OK;
}
static HRESULT STDMETHODCALLTYPE lv_drop_over(IDropTarget *self, DWORD keys, POINTL point, DWORD *effect) { if (!((LunoirDrop *)self)->hint) *effect = 0; else *effect = lv_drop_effect(*effect); return S_OK; }
static HRESULT STDMETHODCALLTYPE lv_drop_leave(IDropTarget *self) { LunoirDrop *s = (LunoirDrop *)self; s->hint = 0; lv_drop_paint(s); return S_OK; }
static HRESULT STDMETHODCALLTYPE lv_drop_drop(IDropTarget *self, IDataObject *data, DWORD keys, POINTL point, DWORD *effect) {
    LunoirDrop *s = (LunoirDrop *)self; char *items = lv_drop_data(data); *effect = items ? lv_drop_effect(*effect) : 0;
    if (items) {
        EnterCriticalSection(&s->lock);
        size_t old = s->pending ? strlen(s->pending) : 0, length = strlen(items);
        char *next = (char *)realloc(s->pending, old + length + 1);
        if (next) { s->pending = next; memcpy(next + old, items, length + 1); }
        LeaveCriticalSection(&s->lock); free(items);
    }
    s->hint = 0; lv_drop_paint(s); return S_OK;
}
static IDropTargetVtbl lv_drop_vtable = {lv_drop_query, lv_drop_addref, lv_drop_release, lv_drop_enter, lv_drop_over, lv_drop_leave, lv_drop_drop};

static LRESULT CALLBACK lv_drop_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    LunoirDrop *s = (LunoirDrop *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (!s) return DefWindowProcW(hwnd, message, wparam, lparam);
    if (message == WM_TIMER) {
        if (!IsWindow(s->parent)) { PostMessageW(hwnd, WM_CLOSE, 0, 0); return 0; }
        POINT p; if (!GetCursorPos(&p)) return 0;
        HWND under = WindowFromPoint(p); HWND root = under ? GetAncestor(under, GA_ROOT) : NULL;
        int over = root == s->parent || root == hwnd;
        int down = lv_key(VK_LBUTTON) || lv_key(VK_RBUTTON);
        if (down && !s->was_down) s->press_outside = !over;
        s->was_down = down;
        int visible = IsWindowVisible(s->parent) && !IsIconic(s->parent) && (s->hint || (down && s->press_outside && over));
        if (visible) { lv_drop_paint(s); if (!s->shown) ShowWindow(hwnd, SW_SHOWNA); }
        else if (s->shown) ShowWindow(hwnd, SW_HIDE);
        s->shown = visible; return 0;
    }
    if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message == WM_CLOSE) { KillTimer(hwnd, 1); RevokeDragDrop(hwnd); DestroyWindow(hwnd); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}
static DWORD WINAPI lv_drop_thread(void *context) {
    LunoirDrop *s = (LunoirDrop *)context;
    HRESULT initialized = OleInitialize(NULL);
    if (FAILED(initialized)) { SetEvent(s->ready); return 0; }
    WNDCLASSW cls = {0}; cls.lpfnWndProc = lv_drop_proc; cls.hInstance = GetModuleHandleW(NULL); cls.lpszClassName = L"LunoirVNativeDrop"; cls.hCursor = LoadCursorW(NULL, IDC_ARROW);
    RegisterClassW(&cls);
    s->hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, cls.lpszClassName, L"Lunoir V drop", WS_POPUP, 0, 0, 1, 1, s->parent, NULL, cls.hInstance, NULL);
    if (s->hwnd) {
        SetWindowLongPtrW(s->hwnd, GWLP_USERDATA, (LONG_PTR)s);
        if (SUCCEEDED(RegisterDragDrop(s->hwnd, &s->target))) {
            SetTimer(s->hwnd, 1, 30, NULL); SetEvent(s->ready);
            MSG msg; while (GetMessageW(&msg, NULL, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        } else { DestroyWindow(s->hwnd); s->hwnd = NULL; SetEvent(s->ready); }
    } else SetEvent(s->ready);
    OleUninitialize(); return 0;
}
static LunoirDrop *lv_drop_create(HWND parent) {
    LunoirDrop *s = (LunoirDrop *)calloc(1, sizeof(*s)); s->target.lpVtbl = &lv_drop_vtable; s->refs = 1; s->parent = parent;
    InitializeCriticalSection(&s->lock); s->ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    s->thread = CreateThread(NULL, 0, lv_drop_thread, s, 0, NULL);
    if (s->thread) WaitForSingleObject(s->ready, 5000); return s;
}
static char *lv_drop_take(LunoirDrop *s) { if (!s) return NULL; EnterCriticalSection(&s->lock); char *p = s->pending; s->pending = NULL; LeaveCriticalSection(&s->lock); return p; }
static void lv_drop_close(LunoirDrop *s) {
    if (!s) return;
    if (s->hwnd) PostMessageW(s->hwnd, WM_CLOSE, 0, 0);
    if (s->thread) { if (WaitForSingleObject(s->thread, 3000) != WAIT_OBJECT_0) return; CloseHandle(s->thread); }
    CloseHandle(s->ready); DeleteCriticalSection(&s->lock); free(s->pending); free(s);
}
#endif
