# BindKey

Tested Zig version: `0.12.0-dev.2536+788a0409a`

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
- [ ] Read mouse events
- [ ] Send mouse inputs
- [ ] Looping functions
