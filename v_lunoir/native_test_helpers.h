#ifndef LUNOIR_NATIVE_TEST_HELPERS_H
#define LUNOIR_NATIVE_TEST_HELPERS_H
#include "drop_win.h"

static HWND lv_test_parent(void) {
    return CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"STATIC", L"Lunoir native integration test", WS_POPUP | WS_VISIBLE, -4000, -4000, 800, 450, NULL, NULL, GetModuleHandleW(NULL), NULL);
}

typedef struct { IDataObject iface; LONG refs; int mode; } LunoirTestData;
static HRESULT STDMETHODCALLTYPE lv_test_data_query(IDataObject *self, REFIID iid, void **out) { *out = self; return S_OK; }
static ULONG STDMETHODCALLTYPE lv_test_data_ref(IDataObject *self) { return 1; }
static HRESULT STDMETHODCALLTYPE lv_test_data_get(IDataObject *self, FORMATETC *format, STGMEDIUM *medium) {
    LunoirTestData *data = (LunoirTestData *)self;
    const wchar_t files[] = L"C:\\Film 一.mkv\0D:\\two.mp4\0";
    const wchar_t text[] = L"not a link\r\n  https://example.test/video?id=one \r\nhttp://ignored.test\0";
    const wchar_t invalid[] = L"nothing playable\0";
    if (format->tymed != TYMED_HGLOBAL) return DV_E_TYMED;
    if (format->cfFormat == CF_HDROP && data->mode == 0) {
        medium->hGlobal = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(DROPFILES) + sizeof(files));
        DROPFILES *header = (DROPFILES *)GlobalLock(medium->hGlobal); header->pFiles = sizeof(DROPFILES); header->fWide = TRUE;
        memcpy((char *)header + sizeof(DROPFILES), files, sizeof(files)); GlobalUnlock(medium->hGlobal);
    } else if (format->cfFormat == CF_UNICODETEXT) {
        const wchar_t *body = data->mode == 2 ? invalid : text;
        size_t length = (wcslen(body) + 1) * sizeof(wchar_t);
        medium->hGlobal = GlobalAlloc(GMEM_MOVEABLE, length);
        void *target = GlobalLock(medium->hGlobal); memcpy(target, body, length); GlobalUnlock(medium->hGlobal);
    } else return DV_E_FORMATETC;
    medium->tymed = TYMED_HGLOBAL; medium->pUnkForRelease = NULL; return S_OK;
}
static IDataObjectVtbl lv_test_data_vtable = {lv_test_data_query, lv_test_data_ref, lv_test_data_ref, lv_test_data_get, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL};

static char *lv_test_drop_payload(int mode, int *effect) {
    LunoirDrop drop = {0}; drop.target.lpVtbl = &lv_drop_vtable; drop.refs = 1; InitializeCriticalSection(&drop.lock);
    LunoirTestData data = {0}; data.iface.lpVtbl = &lv_test_data_vtable; data.mode = mode;
    POINTL point = {0}; DWORD allowed = DROPEFFECT_COPY | DROPEFFECT_LINK;
    lv_drop_enter(&drop.target, &data.iface, 0, point, &allowed);
    if (allowed) lv_drop_drop(&drop.target, &data.iface, 0, point, &allowed);
    *effect = allowed; char *result = drop.pending; DeleteCriticalSection(&drop.lock); return result;
}

static int lv_test_drop_lifecycle(void) {
    HWND parent = lv_test_parent(); LunoirDrop *drop = lv_drop_create(parent); HWND overlay = drop->hwnd;
    int ready = overlay && IsWindow(overlay); lv_drop_close(drop);
    int gone = !IsWindow(overlay); DestroyWindow(parent); return ready && gone;
}
#endif
