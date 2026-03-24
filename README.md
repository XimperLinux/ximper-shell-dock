# ximper-shell-dock

Dock panel.
A component of the Ximper Shell.

Wayland dock with app indicators, autohide, floating/pinned modes, drag-and-drop reordering. Built with Vala, GTK4, libadwaita, gtk4-layer-shell.

Supports Hyprland and (soon) other compositors.

## Build

```sh
meson setup _build
ninja -C _build
./_build/src/ximper-shell-dock
```

## CLI

```sh
ximper-shell-dock --pin <desktop_id>
ximper-shell-dock --unpin <desktop_id>
```

## Config

`~/.config/ximper-shell/dock/config.json`

```json
{
  "mode": "floating",
  "autohide": false,
  "icon_size": 48,
  "layer": 2,
  "pinned_apps": ["org.gnome.Nautilus.desktop"]
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mode` | string | `"floating"` | `"floating"` or `"pinned"` |
| `autohide` | bool | `false` | Hide dock when not in use |
| `icon_size` | int | `48` | Dock icon size in pixels |
| `layer` | int | `2` | Layer shell layer (0=background, 1=bottom, 2=top, 3=overlay) |
| `pinned_apps` | string[] | | List of pinned .desktop IDs |

## D-Bus

`ru.ximperlinux.shell.Dock` at `/ru/ximperlinux/shell/Dock`:
- `GetPinnedApps() → string[]`
- `IsPinned(desktop_id) → bool`
- `Pin(desktop_id)`
- `Unpin(desktop_id)`

## License

GPLv3 — see [LICENSE](LICENSE).
