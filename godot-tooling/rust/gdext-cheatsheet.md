# gdext Cheat Sheet
[Official Godot Docs](https://docs.godotengine.org/en/stable/index.html)
[Gdext Docs](https://godot-rust.github.io/docs/gdext/master/godot/)
[Extension/Other Language support for Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/other_languages.html)

## Entry point
```rust
#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
```
Auto-registers every `#[derive(GodotClass)]` type in the crate. No manual list.

---

## Declaring a class
```rust
#[derive(GodotClass)]
#[class(base=Node2D)]          // default base = RefCounted if omitted
struct Player {
    #[base]
    base: Base<Node2D>,
    speed: f32,
}
```
- `#[class(base=X)]` - inherit from `X` (any Godot class).
- `#[class(tool)]` - runs in-editor too (equivalent of `@tool`), pair with `Engine::singleton().is_editor_hint()` guards in your logic.
- `#[class(init)]` - auto-generate a trivial `init()` using field defaults (`Default` or `#[init(val=...)]` per field), skips writing `IBase::init` yourself.
- `#[base] base: Base<T>` - required if you need to call methods on the underlying Godot object.

## Virtual/lifecycle methods
```rust
#[godot_api]
impl INode2D for Player {
    fn init(base: Base<Node2D>) -> Self { Self { base, speed: 400.0 } }
    fn ready(&mut self) {}
    fn process(&mut self, delta: f64) {}
    fn physics_process(&mut self, delta: f64) {}
    fn input(&mut self, event: Gd<InputEvent>) {}
    fn exit_tree(&mut self) {}
}
```
Trait name is `I<BaseClass>` (`INode`, `IControl`, `ICharacterBody2D`, ...). No leading underscore.

---

## Exposing to the editor / Inspector
```rust
#[derive(GodotClass)]
#[class(base=Node2D)]
struct Player {
    #[base]
    base: Base<Node2D>,

    #[export]                              // shows in Inspector, editable
    max_hp: i32,

    #[export(range = (0.0, 500.0, 1.0))]   // slider with min,max,step
    speed: f32,

    #[export(enum = (Idle, Walk, Run))]    // dropdown
    state: GString,

    #[export(file = "*.png")]              // file picker w/ filter
    icon_path: GString,

    #[var]                                 // gettable/settable via code+GDScript, NOT in Inspector
    hp: i32,

    #[export]
    #[var(get, set = set_hp)]              // custom setter, still exported
    hp2: i32,
}

#[godot_api]
impl Player {
    #[func]
    fn set_hp(&mut self, val: i32) {
        self.hp2 = val.max(0);
    }
}
```
- `#[export]` → Inspector + property system.
- `#[var]` → property system only (get/set from code), no Inspector row.
- Both require the field's type to impl `Var`/`Export` (all built-in Godot types + your own `#[derive(GodotClass)]` types as `Gd<T>` do).

## Methods & signals
```rust
#[godot_api]
impl Player {
    #[func]
    pub fn take_damage(&mut self, amount: i32) {
        self.hp -= amount;
        if self.hp <= 0 {
            self.base_mut().emit_signal("died", &[]);
        }
    }

    #[signal]
    fn died();

    #[signal]
    fn hp_changed(new_hp: i32);
}
```
`#[func]` = callable from GDScript/other extensions/editor. Skip entirely for internal-only Rust logic - plain `impl Player { ... }` blocks (no `#[godot_api]`) are invisible to Godot and cost nothing.

## Constants
```rust
#[godot_api]
impl Player {
    #[constant]
    const MAX_SPEED: f32 = 999.0;
}
```

---

## Loading resources & scenes
```rust
let scene: Gd<PackedScene> = load("res://player.tscn");          // panics if missing/wrong type
let scene: Option<Gd<PackedScene>> = try_load("res://player.tscn"); // fallible

let instance: Gd<Node> = scene.instantiate().unwrap();
let player: Gd<Player> = instance.cast::<Player>();               // panics on mismatch
let player: Option<Gd<Player>> = instance.try_cast::<Player>().ok(); // fallible
```

## Node tree navigation
```rust
// from inside a #[godot_api] impl, self.base() gives &Base<T> context
let hud: Gd<Hud> = self.base().get_node_as("HUD");                // panics if missing/wrong type
let hud: Option<Gd<Hud>> = self.base().try_get_node_as("HUD");    // fallible

let parent: Gd<Node> = self.base().get_parent().unwrap();
let child: Option<Gd<Node>> = self.base().find_child("SomeName");

parent.add_child(&player);
player.queue_free();
```

## Instantiating a class directly (no scene file)
```rust
let node: Gd<Player> = Player::new_alloc();   // for Node-derived (manually managed)
let obj: Gd<MyResource> = MyResource::new_gd(); // for RefCounted-derived (auto memory)
```

---

## Accessing Rust data from a `Gd<T>` handle
```rust
let mut player: Gd<Player> = ...;
player.bind().hp;              // immutable borrow of your struct
player.bind_mut().take_damage(10); // mutable borrow - panics if already borrowed elsewhere
```
Inside your own class's methods, use `self` directly - `bind()`/`bind_mut()` is only for reaching into *other* nodes' Rust state via their `Gd<T>` handle.

## Calling engine singletons
```rust
use godot::classes::{Engine, Input, Os, Time};

Engine::singleton().is_editor_hint();
Input::singleton().is_action_pressed("jump");
Os::singleton().get_name();
Time::singleton().get_ticks_msec();
```

## Connecting signals from Rust
```rust
let callable = self.base().callable("on_died");
other_node.connect("died", &callable);

#[func]
fn on_died(&mut self) { /* ... */ }
```

## Type-erasing your own trait (e.g. dispatching packets to unknown-concrete-type nodes)
```rust
let entry: Box<dyn FnMut(&mut Gd<Node>, &Packet)> = Box::new(move |n, pkt| {
    n.clone().cast::<Player>().bind_mut().accept_packet(pkt);
});
```
Bake the concrete type into a closure at the point where you still know it (spawn time); store the closure, not the type.

---

## Quick reference: what needs `#[godot_api]`
| Need | Where |
|---|---|
| Engine calls your virtual (`_ready`, `_process`...) | `impl I<Base> for T` inside `#[godot_api]` |
| GDScript/editor/other extensions call your method | `#[func]` inside `#[godot_api] impl T` |
| Property shows in Inspector or property system | `#[export]` / `#[var]` on field |
| Pure internal Rust logic, never touched by engine | plain `impl T { ... }`, no macro at all |
