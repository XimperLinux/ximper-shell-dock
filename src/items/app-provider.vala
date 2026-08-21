namespace XimperShellDock {

    public class AppProvider : Object {

        public GenericArray<AppEntry> apps;

        private GenericArray<AppEntry> known_apps;
        private AppInfoMonitor monitor;

        public signal void apps_changed ();

        public AppProvider () {
            apps = new GenericArray<AppEntry> ();
            known_apps = new GenericArray<AppEntry> ();
        }

        public void scan () {
            apps = new GenericArray<AppEntry> ();
            known_apps = new GenericArray<AppEntry> ();

            var all_apps = AppInfo.get_all ();
            foreach (var info in all_apps) {
                if (info is DesktopAppInfo) {
                    var dinfo = (DesktopAppInfo) info;
                    var entry = new AppEntry (dinfo);
                    known_apps.add (entry);
                    if (dinfo.should_show ()) {
                        apps.add (entry);
                    }
                }
            }

            apps.sort ((a, b) => {
                return a.name.collate (b.name);
            });
            known_apps.sort ((a, b) => {
                return a.name.collate (b.name);
            });

            if (monitor == null) {
                monitor = AppInfoMonitor.get ();
                monitor.changed.connect (() => {
                    scan ();
                    apps_changed ();
                });
            }
        }

        public GenericArray<AppEntry> search (string query) {
            var results = new GenericArray<AppEntry> ();
            for (uint i = 0; i < apps.length; i++) {
                if (apps[i].matches (query)) {
                    results.add (apps[i]);
                }
            }
            return results;
        }

        public AppEntry? find_by_desktop_id (string desktop_id) {
            for (uint i = 0; i < known_apps.length; i++) {
                if (known_apps[i].desktop_id == desktop_id) {
                    return known_apps[i];
                }
            }
            return null;
        }

        public AppEntry resolve_running_app (RunningApp running) {
            var entry = find_by_window_metadata (running);
            if (entry != null) return entry;
            return AppEntry.for_window (running);
        }

        private AppEntry? find_by_window_metadata (RunningApp running) {
            var app_id = running.app_class.strip ();
            if (app_id.length == 0) return null;

            // Inspired by KDE Plasma libtaskmanager's metadata resolver:
            // https://invent.kde.org/plasma/plasma-workspace/-/blob/master/libtaskmanager/tasktools.cpp
            // See serviceFromMetadata(), servicesFromEnvironment() and servicesFromCmdLine().
            // KDE first trusts explicit mapping metadata and weighs duplicate matches toward
            // menuId/desktop id closest to the app id. This is important for Steam: game
            // launchers have Exec=steam steam://rungameid/..., but the Steam client window
            // with app_id=steam must resolve to steam.desktop, not a random game.
            var entry = find_by_startup_wm_class (app_id);
            if (entry != null) return entry;

            entry = find_by_desktop_entry_name (app_id);
            if (entry != null) return entry;

            if (app_id.has_prefix ("/")) {
                entry = find_by_desktop_path (app_id);
                if (entry != null) return entry;
                entry = find_by_desktop_path (app_id + ".desktop");
                if (entry != null) return entry;
            }

            entry = find_by_name (app_id);
            if (entry != null) return entry;

            entry = find_steam_game (running);
            if (entry != null) return entry;

            entry = find_from_environment (running.pid);
            if (entry != null) return entry;

            entry = find_from_cmdline (running.pid);
            if (entry != null) return entry;

            return null;
        }

        private AppEntry? find_by_startup_wm_class (string wm_class) {
            var matches = new GenericArray<AppEntry> ();
            for (uint i = 0; i < known_apps.length; i++) {
                var startup = known_apps[i].startup_wm_class;
                if (startup != null && startup.length > 0 &&
                    startup.down () == wm_class.down ()) {
                    matches.add (known_apps[i]);
                }
            }
            return best_menu_id_match (matches, wm_class);
        }

        private AppEntry? find_by_desktop_entry_name (string app_id) {
            var key = app_id.has_suffix (".desktop")
                ? app_id.substring (0, app_id.length - ".desktop".length)
                : app_id;
            var matches = new GenericArray<AppEntry> ();
            for (uint i = 0; i < known_apps.length; i++) {
                var desktop_key = desktop_entry_name (known_apps[i]);
                if (desktop_key.down () == key.down ()) {
                    matches.add (known_apps[i]);
                }
            }
            return best_menu_id_match (matches, key);
        }

        private AppEntry? find_by_name (string name) {
            var matches = new GenericArray<AppEntry> ();
            for (uint i = 0; i < apps.length; i++) {
                if (apps[i].name.down () == name.down ()) {
                    matches.add (apps[i]);
                }
            }
            return best_menu_id_match (matches, name);
        }

        private AppEntry? find_by_desktop_path (string path) {
            for (uint i = 0; i < known_apps.length; i++) {
                if (known_apps[i].filename != null && known_apps[i].filename == path) {
                    return known_apps[i];
                }
            }
            return null;
        }

        private AppEntry? find_steam_game (RunningApp running) {
            var app_id = running.app_class.strip ();
            if (app_id.down () == "steam") return null;

            // KDE can use the Wayland-provided window icon as a final fallback.
            // Niri's JSON API does not expose it, so for Steam games we recover
            // the generated desktop launcher/icon through Steam app id or title.
            // Keep this after app-id/name matching and before pid Exec matching:
            // pid/cmdline can point at the Steam client or pressure-vessel runtime.
            var steam_app_id = steam_app_id_from_string (app_id);
            if (steam_app_id == null) steam_app_id = read_environ_value (running.pid, "SteamAppId");
            if (steam_app_id == null) steam_app_id = read_environ_value (running.pid, "STEAM_APP_ID");
            if (steam_app_id == null) steam_app_id = steam_app_id_from_cmdline (running.pid);

            if (steam_app_id != null && steam_app_id.length > 0) {
                var entry = find_steam_launcher_by_app_id (steam_app_id);
                if (entry != null) return entry;
            }

            return find_steam_launcher_by_title (running.title);
        }

        private AppEntry? find_steam_launcher_by_app_id (string app_id) {
            var rungame = "steam://rungameid/" + app_id;
            var icon_name = "steam_icon_" + app_id;
            for (uint i = 0; i < known_apps.length; i++) {
                var exec = known_apps[i].exec_line ?? "";
                var icon = known_apps[i].icon != null ? known_apps[i].icon.to_string () : "";
                if (exec.contains (rungame) || icon.contains (icon_name)) return known_apps[i];
            }
            return null;
        }

        private AppEntry? find_steam_launcher_by_title (string title) {
            var clean_title = normalize_steam_title (title);
            if (clean_title.length == 0) return null;

            for (uint i = 0; i < known_apps.length; i++) {
                var exec = known_apps[i].exec_line ?? "";
                if (!exec.contains ("steam://rungameid/")) continue;
                if (normalize_steam_title (known_apps[i].name).down () == clean_title.down ()) {
                    return known_apps[i];
                }
            }
            return null;
        }

        private static string normalize_steam_title (string title) {
            var result = title.strip ();
            if (result.has_suffix ("™")) result = result.substring (0, result.length - "™".length).strip ();
            if (result.has_suffix ("®")) result = result.substring (0, result.length - "®".length).strip ();
            return result;
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

        private static string? steam_app_id_from_cmdline (int pid) {
            if (pid <= 0) return null;
            try {
                string cmdline;
                size_t length;
                FileUtils.get_contents ("/proc/%d/cmdline".printf (pid), out cmdline, out length);
                return steam_app_id_from_string (normalize_cmdline (cmdline));
            } catch (Error e) {
            }
            return null;
        }

        private static string? read_environ_value (int pid, string key) {
            if (pid <= 0) return null;
            try {
                string contents;
                size_t length;
                FileUtils.get_contents ("/proc/%d/environ".printf (pid), out contents, out length);
                var prefix = key + "=";
                foreach (var line in contents.split ("\0")) {
                    if (line.has_prefix (prefix)) return line.substring (prefix.length);
                }
            } catch (Error e) {
            }
            return null;
        }

        private AppEntry? find_from_environment (int pid) {
            if (pid <= 0) return null;

            try {
                string contents;
                size_t length;
                FileUtils.get_contents ("/proc/%d/environ".printf (pid), out contents, out length);
                foreach (var line in contents.split ("\0")) {
                    if (line.has_prefix ("BAMF_DESKTOP_FILE_HINT=")) {
                        var path = line.substring ("BAMF_DESKTOP_FILE_HINT=".length);
                        return find_by_desktop_path (path);
                    }
                    if (line.has_prefix ("APPDIR=")) {
                        var appdir = line.substring ("APPDIR=".length);
                        var entry = find_appdir_desktop (appdir);
                        if (entry != null) return entry;
                    }
                }
            } catch (Error e) {
            }
            return null;
        }

        private AppEntry? find_appdir_desktop (string appdir) {
            try {
                var dir = File.new_for_path (appdir);
                var enumerator = dir.enumerate_children (
                    "standard::name,standard::type", FileQueryInfoFlags.NONE, null
                );
                FileInfo info;
                while ((info = enumerator.next_file (null)) != null) {
                    if (info.get_file_type () != FileType.REGULAR) continue;
                    var name = info.get_name ();
                    if (!name.has_suffix (".desktop")) continue;
                    var path = Path.build_filename (appdir, name);
                    var entry = find_by_desktop_path (path);
                    if (entry != null) return entry;
                    try {
                        var dinfo = new DesktopAppInfo.from_filename (path);
                        if (dinfo != null) return new AppEntry (dinfo);
                    } catch (Error e) {
                    }
                }
            } catch (Error e) {
            }
            return null;
        }

        private AppEntry? find_from_cmdline (int pid) {
            if (pid <= 0) return null;

            string cmdline;
            size_t length;
            try {
                FileUtils.get_contents ("/proc/%d/cmdline".printf (pid), out cmdline, out length);
            } catch (Error e) {
                return null;
            }

            var normalized = normalize_cmdline (cmdline);
            if (normalized.length == 0) return null;
            var first_token = first_shell_token (normalized);
            var basename = first_token.length > 0 ? Path.get_basename (first_token) : "";

            var matches = new GenericArray<AppEntry> ();
            for (uint i = 0; i < known_apps.length; i++) {
                var exec = known_apps[i].exec_line;
                if (exec == null || exec.strip ().length == 0) continue;
                var clean_exec = AppEntry.strip_field_codes (exec);
                var exec_first = first_shell_token (clean_exec);
                var exec_base = exec_first.length > 0 ? Path.get_basename (exec_first) : "";

                if (clean_exec.down () == normalized.down () ||
                    exec_first.down () == first_token.down () ||
                    (exec_base.length > 0 && exec_base.down () == basename.down ())) {
                    matches.add (known_apps[i]);
                }
            }
            return best_menu_id_match (matches, basename);
        }

        private static string normalize_cmdline (string cmdline) {
            var result = new StringBuilder ();
            for (int i = 0; i < cmdline.length; i++) {
                result.append_c (cmdline[i] == '\0' ? ' ' : cmdline[i]);
            }
            return result.str.strip ();
        }

        private static string first_shell_token (string command) {
            try {
                string[] argv;
                Shell.parse_argv (command, out argv);
                if (argv.length > 0) return argv[0];
            } catch (Error e) {
            }

            var parts = command.strip ().split (" ", 2);
            return parts.length > 0 ? parts[0] : "";
        }

        private AppEntry? best_menu_id_match (GenericArray<AppEntry> matches, string key) {
            if (matches.length == 0) return null;
            if (matches.length == 1) return matches[0];

            var desktop_file = key.has_suffix (".desktop") ? key.down () : (key + ".desktop").down ();
            var lowered_key = key.down ();

            for (uint i = 0; i < matches.length; i++) {
                if (matches[i].desktop_id.down () == desktop_file) return matches[i];
            }
            for (uint i = 0; i < matches.length; i++) {
                if (matches[i].desktop_id.down ().has_prefix (lowered_key)) return matches[i];
            }
            return matches[0];
        }

        private static string desktop_entry_name (AppEntry entry) {
            return AppEntry.desktop_entry_name (entry.desktop_id);
        }
    }
}
