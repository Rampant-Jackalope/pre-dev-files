// This is the bare minimum required to make a valid gdextension with gdext rust.
// Unlike godot-cpp there is no need to register custom nodes or types.
// Custom nodes are handled by gdext internally.

use godot::prelude::*;

// entry_symbol here MUST match entry_symbol in .gdextension file
struct RjExtension;
#[gdextension(entry_symbol = rj_lib_init)]
unsafe impl ExtensionLibrary for RjExtension {}
