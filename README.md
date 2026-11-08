# lua-files

Lua modules fetched at runtime by my Roblox scripts (via `game:HttpGet` on the
raw file URL, with a cache-busting query string so edits here go live on the
next script run — no need to re-obfuscate or redistribute the host script).

## Contents

- `avatar-lite/ui.lua` — fullscreen UI for **VL Avatar Lite** (the client-side
  avatar changer inside Volleyball Legends), recreating the Catalog Avatar
  Creator game's CatalogGUI layout. The host script keeps all state and logic;
  this module only builds and renders the interface.

Raw URL pattern:

```
https://raw.githubusercontent.com/Nade-is-not-a-dev/lua-files/main/<path>?v=<random>
```
