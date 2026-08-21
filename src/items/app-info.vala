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
        public string? startup_wm_class { get; private set; default = null; }
        public string? executable { get; private set; default = null; }
        public string? exec_line { get; private set; default = null; }
        public string? filename { get; private set; default = null; }
        public bool can_launch { get; private set; default = true; }

        private DesktopAppInfo? app_info;

        public AppEntry (DesktopAppInfo info) {
            this.app_info = info;
            this.desktop_id = info.get_id () ?? info.get_filename ();
            this.name = info.get_display_name () ?? info.get_name ();
            this.generic_name = info.get_generic_name ();
            this.icon = info.get_icon ();
            this.categories = info.get_categories ();
            this.keywords = info.get_keywords ();
            this.startup_wm_class = info.get_string ("StartupWMClass");
            this.executable = info.get_executable ();
            this.exec_line = info.get_commandline ();
            this.filename = info.get_filename ();
        }

        public static AppEntry for_window (RunningApp running) {
            var entry = new AppEntry.from_window (running);
            return entry;
        }

        private AppEntry.from_window (RunningApp running) {
            this.app_info = null;
            this.desktop_id = "window:" + running.app_class;
            this.name = running.title.length > 0 ? running.title : running.app_class;
            this.generic_name = running.app_class;
            this.icon = new ThemedIcon ("application-x-executable");
            this.categories = null;
            this.keywords = null;
            this.startup_wm_class = running.app_class;
            this.executable = null;
            this.exec_line = null;
            this.filename = null;
            this.can_launch = false;
        }

        public bool launch () {
            if (app_info == null) return false;

            // DBusActivatable applications use the standard GApplication object.
            // Calling the well-known bus name without NO_AUTO_START lets D-Bus
            // activate a cold service. Some third-party desktop files declare
            // D-Bus activation without providing a working service, so retain
            // an Exec fallback after the activation attempt fails.
            if (app_info.get_boolean ("DBusActivatable")) {
                try {
                    var bus_name = get_dbus_name ();
                    var conn = Bus.get_sync (BusType.SESSION, null);
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
                    SpawnFlags.SEARCH_PATH,
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
                    SpawnFlags.SEARCH_PATH,
                    () => { c_setsid (); }, null
                );
                return true;
            } catch (Error e) {
                warning ("Failed to launch %s via Exec fallback: %s", name, e.message);
                return false;
            }
        }

        public bool matches_window_class (string window_class) {
            var app_id = desktop_entry_name (desktop_id);
            if (window_class.down () == app_id.down ()) return true;

            var parts = app_id.split (".");
            if (parts.length > 0 &&
                window_class.down () == parts[parts.length - 1].down ()) return true;

            var startup_wm_class = this.startup_wm_class;
            if (startup_wm_class != null && startup_wm_class.length > 0 &&
                window_class.down () == startup_wm_class.down ()) return true;

            // Steam game launchers all execute the Steam client itself
            // (Exec=steam steam://rungameid/...).  Do not treat a Steam client
            // window with app_id/class "steam" as every pinned game.  Only
            // match such launchers when the compositor exposes the concrete
            // Steam application id (for example steam_app_620 or steam-620).
            var steam_app_id = get_steam_app_id ();
            if (steam_app_id != null) {
                var window_steam_app_id = steam_app_id_from_string (window_class);
                return window_steam_app_id != null && window_steam_app_id == steam_app_id;
            }

            // Some Wayland applications use the executable name as app_id
            // rather than their reverse-DNS desktop ID and do not provide
            // StartupWMClass (for example org.gnome.DiskUtility/gnome-disks).
            var executable = this.executable;
            return executable != null && executable.length > 0 &&
                window_class.down () == Path.get_basename (executable).down ();
        }

        private string? get_steam_app_id () {
            var exec = exec_line ?? "";
            var id = steam_app_id_from_rungame_url (exec);
            if (id != null) return id;

            var icon_name = icon != null ? icon.to_string () : "";
            return steam_app_id_from_string (icon_name);
        }

        private static string? steam_app_id_from_rungame_url (string value) {
            try {
                var regex = new Regex ("steam://rungameid/([0-9]+)", RegexCompileFlags.CASELESS);
                MatchInfo match;
                if (regex.match (value, 0, out match)) return match.fetch (1);
            } catch (Error e) {
            }
            return null;
        }

        private static string? steam_app_id_from_string (string value) {
            try {
                var regex = new Regex ("(?:steam_app_|steam_appid_|steam-)([0-9]+)", RegexCompileFlags.CASELESS);
                MatchInfo match;
                if (regex.match (value, 0, out match)) return match.fetch (1);
            } catch (Error e) {
            }
            return null;
        }

        public string[] list_actions () {
            if (app_info == null) return {};
            return app_info.list_actions ();
        }

        public string get_action_name (string action_id) {
            if (app_info == null) return action_id;
            return app_info.get_action_name (action_id);
        }

        public void launch_action (string action_id) {
            if (app_info == null) return;
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
                    SpawnFlags.SEARCH_PATH,
                    () => { c_setsid (); },
                    null
                );
            } catch (Error e) {
                warning ("Failed to launch action %s for %s: %s", action_id, name, e.message);
            }
        }

        public static string desktop_entry_name (string id) {
            return id.has_suffix (".desktop")
                ? id.substring (0, id.length - ".desktop".length)
                : id;
        }

        public static string strip_field_codes (string exec) {
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
