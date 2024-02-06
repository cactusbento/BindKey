# BindKey

Tested Zig version: `0.12.0-dev.2587+a1b607acb`

A Zig library for rebinding keys to callback functions.

## Example 

See `src/main.zig` for an example of how to use this library.

## Modules

* `"bindkey"` The library itself.
  - Depends on [`"libevdev"`](https://github.com/cactusbento/libevdev-zig)
    - Which links `libc` and `libevdev` that is provided by your system.


## Features/TODOs

- [x] Read Keyboard events
- [x] Capture all keyboard inputs
- [x] Send Keyboard Inputs
- [x] Read mouse events
- [x] Send mouse inputs
- [x] Looping functions (Jank)
