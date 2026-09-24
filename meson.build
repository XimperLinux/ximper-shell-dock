project('ximper-shell-dock', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.62.0',
)

i18n = import('i18n')

conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
configure_file(output: 'config.h', configuration: conf)

subdir('src')
config_test = executable('dock-config-test',
  files('tests/config-test.vala', 'src/config.vala',
        'src/folders/dock-config-types.vala',
        'src/tools/layer-shell-helper.vala'),
  dependencies: dock_deps,
)
test('config', config_test)

exec_test = executable('dock-exec-test',
  files('tests/exec-test.vala', 'src/items/app-info.vala'),
  dependencies: dock_deps,
)
test('desktop-entry-exec', exec_test)

subdir('data')
subdir('po')
