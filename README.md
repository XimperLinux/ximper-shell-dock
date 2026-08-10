# ximper-shell-dock

![Dock demo](assets/dock-demo.gif)

Dock panel.
A component of the Ximper Shell.

Wayland dock with app indicators, autohide, floating/pinned modes, macOS-style folder Stacks, hover magnification, launch bounce, and drag-and-drop. Built with Vala, GTK4, libadwaita, gtk4-layer-shell.

Supports Hyprland and Niri through compositor helpers.

## Features

- Floating and pinned layouts, with optional autohide.
- Running and focused-app indicators; unpinned running applications are shown separately.
- Hover magnification wave with configurable scale, neighbour reach, and response speed; clicks and drag-and-drop also work over the enlarged part of an icon.
- Optional launch bounce that continues until the application window is detected.
- Dock width adapts to the monitor: icons shrink only when the configured size cannot fit.
- Reorder application icons and Folder Stacks by dragging them; drop an application from the tile menu to pin it. Reorder feedback keeps a stable animated gap.
- Add folders as Dock Stacks by dragging a directory from the file manager onto any part of the dock, or through the dock context menu.
  Stack contents open as a scrollable grid, list, or fan; file previews use the system thumbnail cache and items can be dragged into other applications.
- Optional Trash at the end of the dock: open it with a click, move files there by dropping them, and empty it from its context menu. Its icon reflects whether Trash contains files.
- Dock contents are kept in sync across all monitors as soon as applications or Folder Stacks are added, removed, or reordered.

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

## Compositor Support

The dock tracks running and focused windows through compositor-specific helpers:

- Hyprland: event socket (`.socket2.sock`) plus `hyprctl` for snapshots, focus, and close actions.
- Niri: `niri msg --json windows` plus `event-stream`; focus and close actions use Niri window IDs.

## Config

`~/.config/ximper-shell/dock/config.json`

```json
{
  "mode": "floating",
  "autohide": false,
  "show_trash": false,
  "magnify_on_hover": false,
  "bounce_on_launch": false,
  "bounce_duration": 200,
  "magnify_scale": 135,
  "magnify_radius": 2.0,
  "magnify_animation_duration": 120,
  "icon_size": 48,
  "layer": 2,
  "launcher_fallback": "wofi --show drun",
  "pinned_apps": ["org.gnome.Nautilus.desktop"],
  "dock_items": ["app:org.gnome.Nautilus.desktop"],
  "dock_folders": [{
    "path": "/home/user/Documents",
    "display": "stack",
    "view": "grid",
    "sort": "name"
  }]
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `mode` | string | `"floating"` | `"floating"` or `"pinned"` |
| `autohide` | bool | `false` | Hide dock when not in use |
| `show_trash` | bool | `false` | Show the system Trash after Folder Stacks at the end of the dock |
| `magnify_on_hover` | bool | `false` | Enable the hover magnification wave |
| `magnify_scale` | int | `135` | Maximum hovered icon size, as a percentage |
| `magnify_radius` | float | `2.0` | Wave reach in icon widths on each side |
| `magnify_animation_duration` | int | `120` | Wave response time in milliseconds |
| `bounce_on_launch` | bool | `false` | Bounce an icon while its application starts |
| `bounce_duration` | int | `200` | Upward bounce duration in milliseconds |
| `icon_size` | int | `48` | Dock icon size in pixels |
| `layer` | int | `2` | Layer shell layer (0=background, 1=bottom, 2=top, 3=overlay) |
| `launcher_fallback` | string | `"wofi --show drun"` | Command to run when tile menu is unavailable |
| `pinned_apps` | string[] | | Compatibility view of pinned application desktop IDs; kept in sync with `dock_items` |
| `dock_items` | string[] | | Ordered application entries in `app:<desktop-id>` format |
| `dock_folders` | object[] | | Folder Stacks; see below |

### Custom CSS

Create `~/.config/ximper-shell/dock/style.css` to override the dock's
appearance without changing installed files. This stylesheet is loaded with
user priority, so its rules take precedence over the bundled stylesheet. Restart
the dock after editing it.

```sh
mkdir -p ~/.config/ximper-shell/dock
```

For example, to adjust the dock background and its floating shadow:

```css
.dock-content {
  background: @window_bg_color;
}

.dock-window.floating .dock-content {
  box-shadow: 0 1px 3px @headerbar_shade_color;
}
```

Useful selectors include `.dock-window`, `.dock-window.floating`,
`.dock-window.pinned`, `.dock-content`, `.dock-icon`,
`.dock-indicator`, and `.dock-folder-item`. GTK/libadwaita theme colors such as
`@window_bg_color`, `@headerbar_bg_color`, and `@accent_bg_color` follow the
active system theme.

### Folder Stack options

Each `dock_folders` entry has an absolute `path` and optional presentation settings:

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `display` | `"folder"`, `"stack"` | `"stack"` | Dock icon appearance |
| `view` | `"grid"`, `"list"`, `"fan"` | `"grid"` | Layout when the folder is opened |
| `sort` | `"name"`, `"modified"`, `"kind"` | `"name"` | Item ordering |

Use the folder's context menu to change these options or remove the Stack. Folders are kept in their own section on the right side of the dock. Drag a directory onto an existing Folder Stack to insert it immediately after that Stack.

### Trash

Enable `show_trash` in the settings window or configuration file to add the system Trash to the far end of the dock. Click it to open `trash:///`; drop files onto it to move them to Trash. The context menu provides **Empty Trash…** and asks for confirmation before permanently deleting its contents.

## D-Bus

`ru.ximperlinux.shell.Dock` at `/ru/ximperlinux/shell/Dock`:
- `GetPinnedApps() → string[]`
- `IsPinned(desktop_id) → bool`
- `Pin(desktop_id)`
- `Unpin(desktop_id)`

## License

GPLv3 — see [LICENSE](LICENSE).
