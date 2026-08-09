dock_deps = [
  dependency('gtk4', version: '>= 4.12'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gtk4-layer-shell-0', version: '>= 1.0'),
  dependency('json-glib-1.0'),
  dependency('gio-unix-2.0'),
  meson.get_compiler('vala').find_library('posix'),
]

dock_sources = files(
  'main.vala',
  'application.vala',
  'config.vala',
  'app-info.vala',
  'app-provider.vala',
  'settings-window.vala',
  'dock-window.vala',
  'dock-icon.vala',
  'folder-dock-icon.vala',
  'folder-settings-window.vala',
  'dock-trigger.vala',
  'layer-shell-helper.vala',
  'compositor-helper.vala',
  'hyprland-helper.vala',
  'niri-helper.vala',
  'window-tracker.vala',
  'dbus-service.vala',
)

executable('ximper-shell-dock', dock_sources,
  dependencies: dock_deps,
  c_args: ['-w'],
  install: true,
)
