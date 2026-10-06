#include "desktop_native.h"

#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/rect2i.hpp>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <commctrl.h>
#endif

using namespace godot;

DesktopNative *DesktopNative::singleton = nullptr;

DesktopNative *DesktopNative::get_singleton() {
	return singleton;
}

DesktopNative::DesktopNative() {
	singleton = this;
}

DesktopNative::~DesktopNative() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

void DesktopNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_click_through", "window_id", "enabled"), &DesktopNative::set_click_through);
	ClassDB::bind_method(D_METHOD("is_click_through", "window_id"), &DesktopNative::is_click_through);
	ClassDB::bind_method(D_METHOD("hide_from_taskbar", "window_id"), &DesktopNative::hide_from_taskbar);
	ClassDB::bind_method(D_METHOD("reassert_topmost", "window_id"), &DesktopNative::reassert_topmost);
	ClassDB::bind_method(D_METHOD("no_activate_on_click", "window_id"), &DesktopNative::no_activate_on_click);
	ClassDB::bind_method(D_METHOD("get_idle_seconds"), &DesktopNative::get_idle_seconds);
	ClassDB::bind_method(D_METHOD("get_taskbar_info"), &DesktopNative::get_taskbar_info);
	ClassDB::bind_method(D_METHOD("is_fullscreen_app_active"), &DesktopNative::is_fullscreen_app_active);
}

#ifdef _WIN32
static HWND _hwnd(int64_t p_window_id) {
	DisplayServer *ds = DisplayServer::get_singleton();
	if (!ds) {
		return nullptr;
	}
	return (HWND)(intptr_t)ds->window_get_native_handle(DisplayServer::WINDOW_HANDLE, (int32_t)p_window_id);
}
#endif

void DesktopNative::set_click_through(int64_t p_window_id, bool p_enabled) {
#ifdef _WIN32
	HWND hwnd = _hwnd(p_window_id);
	if (!hwnd) {
		return;
	}
	LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
	LONG_PTR wanted = p_enabled ? (ex | WS_EX_LAYERED | WS_EX_TRANSPARENT) : (ex & ~WS_EX_TRANSPARENT);
	if (wanted == ex) {
		return;
	}
	bool was_layered = (ex & WS_EX_LAYERED) != 0;
	SetWindowLongPtrW(hwnd, GWL_EXSTYLE, wanted);
	if (!was_layered && (wanted & WS_EX_LAYERED)) {
		// Una ventana layered sin atributos no se compone: forzamos opacidad total.
		SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
	}
#endif
}

bool DesktopNative::is_click_through(int64_t p_window_id) const {
#ifdef _WIN32
	HWND hwnd = _hwnd(p_window_id);
	if (!hwnd) {
		return false;
	}
	return (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TRANSPARENT) != 0;
#else
	return false;
#endif
}

void DesktopNative::hide_from_taskbar(int64_t p_window_id) {
#ifdef _WIN32
	HWND hwnd = _hwnd(p_window_id);
	if (!hwnd) {
		return;
	}
	LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
	LONG_PTR wanted = (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
	if (wanted != ex) {
		SetWindowLongPtrW(hwnd, GWL_EXSTYLE, wanted);
		SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
	}
	// La barra no siempre se entera del cambio de estilo: quitamos la pestaña explícitamente.
	ITaskbarList *tbl = nullptr;
	HRESULT hr_init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_ITaskbarList, (void **)&tbl)) && tbl) {
		if (SUCCEEDED(tbl->HrInit())) {
			tbl->DeleteTab(hwnd);
		}
		tbl->Release();
	}
	if (SUCCEEDED(hr_init)) {
		CoUninitialize();
	}
#endif
}

void DesktopNative::reassert_topmost(int64_t p_window_id) {
#ifdef _WIN32
	HWND hwnd = _hwnd(p_window_id);
	if (!hwnd) {
		return;
	}
	SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
#endif
}

#ifdef _WIN32
// Hacer clic en la ventana no la activa (no roba el foco ni la sube), pero el botón de la
// barra de tareas o Alt-Tab sí pueden traerla al frente (a diferencia de WS_EX_NOACTIVATE).
static LRESULT CALLBACK _no_activate_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	if (msg == WM_MOUSEACTIVATE) {
		return MA_NOACTIVATE;
	}
	if (msg == WM_NCDESTROY) {
		RemoveWindowSubclass(hwnd, _no_activate_proc, id);
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}
#endif

void DesktopNative::no_activate_on_click(int64_t p_window_id) {
#ifdef _WIN32
	HWND hwnd = _hwnd(p_window_id);
	if (!hwnd) {
		return;
	}
	// Idempotente: con el mismo id, SetWindowSubclass solo actualiza los datos.
	SetWindowSubclass(hwnd, _no_activate_proc, 1, 0);
	LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
	if (ex & WS_EX_NOACTIVATE) {
		SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex & ~WS_EX_NOACTIVATE);
	}
#endif
}

double DesktopNative::get_idle_seconds() const {
#ifdef _WIN32
	LASTINPUTINFO lii;
	lii.cbSize = sizeof(LASTINPUTINFO);
	if (!GetLastInputInfo(&lii)) {
		return 0.0;
	}
	DWORD now = GetTickCount();
	return (double)(DWORD)(now - lii.dwTime) / 1000.0;
#else
	return 0.0;
#endif
}

Dictionary DesktopNative::get_taskbar_info() const {
	Dictionary d;
#ifdef _WIN32
	APPBARDATA abd = {};
	abd.cbSize = sizeof(APPBARDATA);
	if (SHAppBarMessage(ABM_GETTASKBARPOS, &abd)) {
		d["rect"] = Rect2i(abd.rc.left, abd.rc.top, abd.rc.right - abd.rc.left, abd.rc.bottom - abd.rc.top);
		d["edge"] = (int64_t)abd.uEdge;
	}
	APPBARDATA abs = {};
	abs.cbSize = sizeof(APPBARDATA);
	UINT_PTR state = SHAppBarMessage(ABM_GETSTATE, &abs);
	d["autohide"] = (state & ABS_AUTOHIDE) != 0;
#endif
	return d;
}

bool DesktopNative::is_fullscreen_app_active() const {
#ifdef _WIN32
	QUERY_USER_NOTIFICATION_STATE st;
	if (SUCCEEDED(SHQueryUserNotificationState(&st))) {
		return st == QUNS_BUSY || st == QUNS_RUNNING_D3D_FULL_SCREEN || st == QUNS_PRESENTATION_MODE;
	}
#endif
	return false;
}
