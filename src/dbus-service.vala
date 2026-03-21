namespace XimperShellDock {

    [DBus (name = "ru.ximperlinux.shell.Dock")]
    public class DockDBusService : Object {

        private weak Application app;

        public DockDBusService (Application app) {
            this.app = app;
        }

        public string[] get_pinned_apps () throws DBusError, IOError {
            var pinned = app.config.pinned_apps;
            if (pinned == null || pinned.length == 0) {
                return {};
            }
            var result = new string[pinned.length];
            for (uint i = 0; i < pinned.length; i++) {
                result[i] = pinned[i];
            }
            return result;
        }

        public bool is_pinned (string desktop_id) throws DBusError, IOError {
            var pinned = app.config.pinned_apps;
            if (pinned == null) return false;
            for (uint i = 0; i < pinned.length; i++) {
                if (pinned[i] == desktop_id) return true;
            }
            return false;
        }

        public void pin (string desktop_id) throws DBusError, IOError {
            app.pin_app (desktop_id);
        }

        public void unpin (string desktop_id) throws DBusError, IOError {
            app.unpin_app (desktop_id);
        }
    }
}
