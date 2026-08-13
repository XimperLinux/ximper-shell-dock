namespace XimperShellDock {

    [CCode (cname = "setsid", cheader_filename = "unistd.h")]
    private static extern int c_setsid ();

    public class AppEntry : Object {

        private const string DBUS_APPLICATION_OBJECT_PATH = "/org/freedesktop/Application";

        public string desktop_id { get; private set; }
        public string name { get; private set; }
        public string? generic_name { get; private set; }
        public Icon? icon { get; private set; }
        public string? categories { get; private set; }
        public string[]? keywords { get; private set; }

        private DesktopAppInfo app_info;

        public AppEntry (DesktopAppInfo info) {
            this.app_info = info;
            this.desktop_id = info.get_id () ?? info.get_filename ();
            this.name = info.get_display_name () ?? info.get_name ();
            this.generic_name = info.get_generic_name ();
            this.icon = info.get_icon ();
            this.categories = info.get_categories ();
            this.keywords = info.get_keywords ();
        }

        public bool launch () {
            // DBusActivatable applications use the standard GApplication object.
            // Some third-party desktop files declare D-Bus activation without
            // providing an activatable service, so retain an Exec fallback.
            if (app_info.get_boolean ("DBusActivatable")) {
                try {
                    var bus_name = get_dbus_name ();
                    var conn = Bus.get_sync (BusType.SESSION, null);
                    if (!has_dbus_owner (conn, bus_name)) {
                        warning ("No D-Bus owner for %s; launching Exec directly", bus_name);
                        return launch_exec_fallback ();
                    }
                    conn.call_sync (
                        bus_name, DBUS_APPLICATION_OBJECT_PATH,
                        "org.freedesktop.Application", "Activate",
                        new Variant.tuple ({ new Variant ("a{sv}", null) }),
                        null, DBusCallFlags.NONE, 2000, null
                    );
                    return true;
                } catch (Error e) {
                    warning ("D-Bus activation failed for %s: %s; falling back to Exec", desktop_id, e.message);
                    return launch_exec_fallback ();
                }
            }

            // Fallback — spawn with setsid so child survives panel death
            try {
                var context = Gdk.Display.get_default ().get_app_launch_context ();
                return app_info.launch_uris_as_manager (
                    new List<string> (), context,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    () => { c_setsid (); },
                    null
                );
            } catch (Error e) {
                warning ("Failed to launch %s: %s", name, e.message);
                return false;
            }
        }

        private string get_dbus_name () {
            return desktop_id.has_suffix (".desktop")
                ? desktop_id.substring (0, desktop_id.length - ".desktop".length)
                : desktop_id;
        }

        private bool has_dbus_owner (DBusConnection conn, string bus_name) throws Error {
            var result = conn.call_sync (
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "NameHasOwner",
                new Variant.tuple ({ new Variant.string (bus_name) }),
                new VariantType ("(b)"),
                DBusCallFlags.NONE, 500, null
            );
            bool owned;
            result.get ("(b)", out owned);
            return owned;
        }

        private bool launch_exec_fallback () {
            try {
                var exec_line = app_info.get_commandline ();
                if (exec_line == null || exec_line.strip ().length == 0) {
                    warning ("Cannot fall back to Exec for %s: Exec is empty", desktop_id);
                    return false;
                }

                string[] argv;
                Shell.parse_argv (strip_field_codes (exec_line), out argv);
                Process.spawn_async (
                    app_info.get_string ("Path"), argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    () => { c_setsid (); }, null
                );
                return true;
            } catch (Error e) {
                warning ("Failed to launch %s via Exec fallback: %s", name, e.message);
                return false;
            }
        }

        public bool matches_window_class (string window_class) {
            var app_id = desktop_id.replace (".desktop", "");
            if (window_class.down () == app_id.down ()) return true;

            var parts = app_id.split (".");
            if (parts.length > 0 &&
                window_class.down () == parts[parts.length - 1].down ()) return true;

            var startup_wm_class = app_info.get_string ("StartupWMClass");
            return startup_wm_class != null && startup_wm_class.length > 0 &&
                window_class.down () == startup_wm_class.down ();
        }

        public string[] list_actions () {
            return app_info.list_actions ();
        }

        public string get_action_name (string action_id) {
            return app_info.get_action_name (action_id);
        }

        public void launch_action (string action_id) {
            try {
                var keyfile = new KeyFile ();
                keyfile.load_from_file (app_info.get_filename (), KeyFileFlags.NONE);
                var group = "Desktop Action " + action_id;
                if (!keyfile.has_group (group)) return;

                var exec_line = keyfile.get_string (group, "Exec");
                exec_line = strip_field_codes (exec_line);

                string[] argv;
                Shell.parse_argv (exec_line, out argv);
                Process.spawn_async (
                    null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    () => { c_setsid (); },
                    null
                );
            } catch (Error e) {
                warning ("Failed to launch action %s for %s: %s", action_id, name, e.message);
            }
        }

        private static string strip_field_codes (string exec) {
            var result = new StringBuilder ();
            for (int i = 0; i < exec.length; i++) {
                if (exec[i] == '%' && i + 1 < exec.length) {
                    var code = exec[i + 1];
                    if ("uUfFickdDnNvm".contains (code.to_string ())) {
                        i++;
                        continue;
                    }
                }
                result.append_c (exec[i]);
            }
            return result.str.strip ();
        }

        public bool matches (string query) {
            var q = query.down ();

            if (name.down ().contains (q)) return true;
            if (generic_name != null && generic_name.down ().contains (q)) return true;
            if (categories != null && categories.down ().contains (q)) return true;

            if (keywords != null) {
                foreach (var kw in keywords) {
                    if (kw.down ().contains (q)) return true;
                }
            }

            return false;
        }
    }
}
