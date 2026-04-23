namespace XimperShellDock {

    public class Application : Adw.Application {

        public ConfigManager config { get; private set; }
        public AppProvider app_provider { get; private set; }
        public WindowTracker window_tracker { get; private set; }

        private GenericArray<DockWindow> dock_windows;
        private GenericArray<DockTrigger> dock_triggers;
        private DockDBusService? dbus_service;

        private const OptionEntry[] OPTIONS = {
            { "pin", 'p', 0, OptionArg.STRING, null, "Pin app to dock", "DESKTOP_ID" },
            { "unpin", 'u', 0, OptionArg.STRING, null, "Unpin app from dock", "DESKTOP_ID" },
            { null }
        };

        public Application () {
            Object (
                application_id: "ru.ximperlinux.shell.Dock",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
            dock_windows = new GenericArray<DockWindow> ();
            dock_triggers = new GenericArray<DockTrigger> ();
            add_main_option_entries (OPTIONS);
        }

        protected override void startup () {
            base.startup ();

            config = new ConfigManager ();
            config.load ();

            app_provider = new AppProvider ();
            app_provider.scan ();

            window_tracker = new WindowTracker ();
            window_tracker.start ();

            load_css ();
        }

        protected override bool dbus_register (DBusConnection conn, string object_path) throws Error {
            base.dbus_register (conn, object_path);
            dbus_service = new DockDBusService (this);
            conn.register_object ("/ru/ximperlinux/shell/Dock", dbus_service);
            return true;
        }

        protected override int command_line (ApplicationCommandLine cmdline) {
            var options = cmdline.get_options_dict ();

            activate ();

            string pin_id;
            if (options.lookup ("pin", "s", out pin_id)) {
                pin_app (pin_id);
                return 0;
            }

            string unpin_id;
            if (options.lookup ("unpin", "s", out unpin_id)) {
                unpin_app (unpin_id);
                return 0;
            }

            return 0;
        }

        protected override void activate () {
            if (dock_windows.length > 0) return;

            // Create dock on each monitor
            var display = Gdk.Display.get_default ();
            var monitors = display.get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = (Gdk.Monitor) monitors.get_item (i);
                create_dock_for_monitor (monitor);
            }

            setup_autohide ();

            config.notify["autohide"].connect (() => {
                setup_autohide ();
            });

            config.notify["dock-mode"].connect (() => {
                for (uint i = 0; i < dock_windows.length; i++) {
                    dock_windows[i].apply_mode ();
                }
                setup_autohide ();
            });

            window_tracker.windows_changed.connect (() => {
                for (uint i = 0; i < dock_windows.length; i++) {
                    dock_windows[i].update_indicators ();
                }
            });

            // Apply already-collected running state immediately
            for (uint i = 0; i < dock_windows.length; i++) {
                dock_windows[i].update_indicators ();
            }

            if (!config.autohide) {
                for (uint i = 0; i < dock_windows.length; i++) {
                    dock_windows[i].set_visible (true);
                }
            }
        }

        private void create_dock_for_monitor (Gdk.Monitor monitor) {
            var dock = new DockWindow (this, monitor);
            dock.grid_requested.connect (() => {
                toggle_grid ();
            });
            add_window (dock);
            dock_windows.add (dock);
        }

        private void toggle_grid () {
            for (int attempt = 0; attempt < 3; attempt++) {
                try {
                    var conn = Bus.get_sync (BusType.SESSION, null);
                    conn.call_sync (
                        "ru.ximperlinux.shell.TileMenu",
                        "/ru/ximperlinux/shell/TileMenu",
                        "ru.ximperlinux.shell.TileMenu",
                        "Toggle",
                        null, null,
                        DBusCallFlags.NONE, 500, null
                    );
                    return;
                } catch (Error e) {
                    if (attempt < 2) {
                        Thread.usleep (100000);
                        continue;
                    }
                    try {
                        Process.spawn_command_line_async (config.launcher_fallback);
                    } catch (Error e2) {
                        warning ("Failed to toggle grid: %s", e.message);
                    }
                }
            }
        }

        protected override void shutdown () {
            window_tracker.stop ();
            base.shutdown ();
        }

        public void pin_app (string desktop_id) {
            var pinned = config.pinned_apps;
            if (pinned == null) {
                pinned = new GenericArray<string> ();
            }
            for (uint i = 0; i < pinned.length; i++) {
                if (pinned[i] == desktop_id) return;
            }
            pinned.add (desktop_id);
            config.pinned_apps = pinned;
            config.save ();
            for (uint i = 0; i < dock_windows.length; i++) {
                dock_windows[i].rebuild_dock ();
            }
        }

        public void unpin_app (string desktop_id) {
            var new_pinned = new GenericArray<string> ();
            var pinned = config.pinned_apps;
            if (pinned == null) return;
            for (uint i = 0; i < pinned.length; i++) {
                if (pinned[i] != desktop_id) {
                    new_pinned.add (pinned[i]);
                }
            }
            config.pinned_apps = new_pinned;
            config.save ();
            for (uint i = 0; i < dock_windows.length; i++) {
                dock_windows[i].rebuild_dock ();
            }
        }

        private void setup_autohide () {
            if (config.autohide) {
                if (dock_triggers.length == 0) {
                    for (uint i = 0; i < dock_windows.length; i++) {
                        var dock = dock_windows[i];
                        var display = Gdk.Display.get_default ();
                        var monitors = display.get_monitors ();
                        if (i < monitors.get_n_items ()) {
                            var monitor = (Gdk.Monitor) monitors.get_item (i);
                            var trigger = new DockTrigger (this, monitor);
                            trigger.trigger_activated.connect (() => {
                                if (!dock.visible) {
                                    dock.show_animated ();
                                }
                            });
                            dock.set_trigger (trigger);
                            add_window (trigger);
                            dock_triggers.add (trigger);
                        }
                    }
                }

                for (uint i = 0; i < dock_triggers.length; i++) {
                    dock_triggers[i].present ();
                }
                for (uint i = 0; i < dock_windows.length; i++) {
                    dock_windows[i].enable_autohide (true);
                    dock_windows[i].set_visible (false);
                }
            } else {
                for (uint i = 0; i < dock_triggers.length; i++) {
                    dock_triggers[i].set_visible (false);
                }
                for (uint i = 0; i < dock_windows.length; i++) {
                    dock_windows[i].enable_autohide (false);
                    dock_windows[i].opacity = 1;
                    dock_windows[i].set_visible (true);
                }
            }
        }

        private void load_css () {
            var css_provider = new Gtk.CssProvider ();

            string css_path = Path.build_filename (
                Environment.get_user_data_dir (), "ximper-shell-dock", "ximper-shell-dock.css"
            );

            if (FileUtils.test (css_path, FileTest.EXISTS)) {
                css_provider.load_from_path (css_path);
            } else {
                string system_css = Path.build_filename (
                    "/etc", "xdg", "ximper-shell", "dock", "style.css"
                );
                if (FileUtils.test (system_css, FileTest.EXISTS)) {
                    css_provider.load_from_path (system_css);
                } else {
                    // Dev mode: try relative to binary location (_build/src/../../data)
                    try {
                        string self_path = FileUtils.read_link ("/proc/self/exe");
                        string bin_dir = Path.get_dirname (self_path);
                        string local_css = Path.build_filename (
                            bin_dir, "..", "..", "data", "ximper-shell-dock.css"
                        );
                        if (FileUtils.test (local_css, FileTest.EXISTS)) {
                            css_provider.load_from_path (local_css);
                        }
                    } catch (FileError e) {}
                }
            }

            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (),
                css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            // User custom style.css from config directory
            string user_css = Path.build_filename (
                Environment.get_user_config_dir (), "ximper-shell", "dock", "style.css"
            );
            if (FileUtils.test (user_css, FileTest.EXISTS)) {
                var user_provider = new Gtk.CssProvider ();
                user_provider.load_from_path (user_css);
                Gtk.StyleContext.add_provider_for_display (
                    Gdk.Display.get_default (),
                    user_provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_USER
                );
            }
        }
    }
}
