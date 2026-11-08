# vl-suite

Modular client-side spoof suite for **Volleyball Legends** (Roblox),
built from separate feature modules that are concatenated into one
script and published via GitHub Pages.

Loadstring:

```lua
loadstring(game:HttpGet("https://nade-is-not-a-dev.github.io/vl-suite/vl-suite.lua"))()
```

## Layout

- `suite/` — the modules and the build script (`build.py`
  concatenates the files listed in `suite/manifest.txt`, stamps
  the version from `suite/VERSION`, and writes `dist/vl-suite.lua`).
  See `suite/README.md` for the module list and conventions.
- `.github/workflows/build-suite.yml` — on every push to `suite/**`:
  build, syntax-check with luau-compile, deploy to GitHub Pages.

Everything is client-side only: effects are visible on your own
screen, nothing is sent to the server.
