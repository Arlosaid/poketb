#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

// Utilidades Win32 que Godot no expone: clic a través real (sin recortar el
// render como hace SetWindowRgn), ocultar el botón de la barra de tareas,
// inactividad del sistema e info de la barra / apps a pantalla completa.
class DesktopNative : public Object {
	GDCLASS(DesktopNative, Object);

	static DesktopNative *singleton;

protected:
	static void _bind_methods();

public:
	static DesktopNative *get_singleton();

	DesktopNative();
	~DesktopNative();

	// Hace que la ventana ignore el mouse (los clics llegan a las apps de abajo).
	// Idempotente: solo toca el estilo si cambia.
	void set_click_through(int64_t p_window_id, bool p_enabled);
	bool is_click_through(int64_t p_window_id) const;

	// Quita el botón de la barra de tareas y de Alt-Tab (WS_EX_TOOLWINDOW).
	// Godot puede recalcular el estilo: conviene llamarlo periódicamente.
	void hide_from_taskbar(int64_t p_window_id);

	// Vuelve a poner la ventana encima de todo sin robar el foco.
	void reassert_topmost(int64_t p_window_id);

	// Segundos desde la última entrada de teclado/mouse en el sistema.
	double get_idle_seconds() const;

	// {rect: Rect2i, edge: int (0=left 1=top 2=right 3=bottom), autohide: bool}
	Dictionary get_taskbar_info() const;

	// true si hay una app a pantalla completa (juego, video, presentación).
	bool is_fullscreen_app_active() const;
};

} // namespace godot
