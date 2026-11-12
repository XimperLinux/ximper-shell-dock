namespace XimperShellDock {

    [DBus (name = "ru.ximperlinux.shell.Dock")]
    public class DockDBusService : Object {

        private weak Application app;

        public DockDBusService (Application app) {
            this.app = app;
        }

        public string[] get_pinned_apps () throws DBusError, IOError {
            var items = app.config.dock_items;
            var result = new GenericArray<string> ();
            for (uint i = 0; i < items.length; i++) {
                if (ConfigManager.is_app_item (items[i]))
                    result.add (ConfigManager.item_desktop_id (items[i]));
            }

            var desktop_ids = new string[result.length];
            for (uint i = 0; i < result.length; i++) {
                desktop_ids[i] = result[i];
            }
            return desktop_ids;
        }

        public bool is_pinned (string desktop_id) throws DBusError, IOError {
            return app.config.has_dock_item (ConfigManager.app_item (desktop_id));
        }

        public void pin (string desktop_id) throws DBusError, IOError {
            app.add_dock_item (ConfigManager.app_item (desktop_id));
        }

        public void unpin (string desktop_id) throws DBusError, IOError {
            app.remove_dock_item (ConfigManager.app_item (desktop_id));
        }

        public void reload () throws DBusError, IOError {
            try {
                app.reload_config ();
            } catch (Error e) {
                throw new IOError.FAILED (e.message);
            }
        }
    }
}
