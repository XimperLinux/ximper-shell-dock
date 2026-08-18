dock_deps = [
  dependency('gtk4', version: '>= 4.12'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gtk4-layer-shell-0', version: '>= 1.0'),
  dependency('json-glib-1.0'),
  dependency('gio-unix-2.0'),
  meson.get_compiler('vala').find_library('posix'),
]

dock_sources = files(
  'config.vapi',
  'main.vala',
  'application.vala',
  'config.vala',
  'describe.vala',
  'dbus-service.vala',
  'settings-window.vala',

  'dock/dock-window.vala',
  'dock/dock-wave-icon.vala',
  'dock/dock-item-gap-controller.vala',
  'dock/dock-icon.vala',
  'dock/dock-trigger.vala',

  'folders/dock-config-types.vala',
  'folders/folder-list-item.vala',
  'folders/folder-file-utils.vala',
  'folders/folder-dock-icon.vala',
  'folders/folder-stack-window.vala',
  'folders/folder-settings-window.vala',

  'items/app-info.vala',
  'items/app-provider.vala',
  'items/trash-dock-icon.vala',

  'compositor/compositor-helper.vala',
  'compositor/hyprland-helper.vala',
  'compositor/niri-helper.vala',
  'compositor/window-tracker.vala',

  'tools/layer-shell-helper.vala',
)

executable('ximper-shell-dock', dock_sources,
  dependencies: dock_deps,
  include_directories: include_directories('..'),
  c_args: ['-DGETTEXT_PACKAGE="ximper-shell-dock"', '-w'],
  install: true,
)
