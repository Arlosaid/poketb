#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "desktop_native.h"

using namespace godot;

static DesktopNative *desktop_native = nullptr;

void initialize_desktop_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DesktopNative);
	desktop_native = memnew(DesktopNative);
	Engine::get_singleton()->register_singleton("DesktopNative", desktop_native);
}

void uninitialize_desktop_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("DesktopNative");
	memdelete(desktop_native);
	desktop_native = nullptr;
}

extern "C" {
GDExtensionBool GDE_EXPORT desktop_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_desktop_native);
	init_obj.register_terminator(uninitialize_desktop_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
