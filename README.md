# trollyodin

A native Windows (also Linux/macOS) re-implementation of [Zolly](https://zolly.app)-style perspective study, written in [Odin](https://odin-lang.org) with `vendor:raylib` for rendering and raygui (bundled in `vendor:raylib`) for the GUI.

## Build & run

    odin run src -out:trollyodin.exe

## Features

- Base forms: sphere, cube, triangle (tetrahedron)
- Orbit view (drag left mouse), dolly (mouse wheel)
- Field of view with "dolly zoom" lock (keeps subject size while FOV changes)
- Horizon / eye-level line, ground grid
- Lens distortion (barrel/pincushion) via shader
- Object rotation, wireframe overlay, orthographic toggle
- Reset view (R)
