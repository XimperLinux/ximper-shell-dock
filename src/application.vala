namespace XimperShellDock {

    public class Application : Adw.Application {

        public ConfigManager config { get; private set; }
        public AppProvider app_provider { get; private set; }
        public WindowTracker window_tracker { get; private set; }

        private GenericArray<DockWindow> dock_windows;
        private GenericArray<DockTrigger> dock_triggers;
        private DockDBusService? dbus_service;
        private bool activated = false;

        private OptionEntry[] options;

        public Application () {
            Object (
                application_id: "ru.ximperlinux.shell.Dock",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
            dock_windows = new GenericArray<DockWindow> ();
            dock_triggers = new GenericArray<DockTrigger> ();
            options = {
                { "add-item", 'a', 0, OptionArg.STRING, null, _("Add an item to dock"), _("ITEM") },
                { "remove-item", 'r', 0, OptionArg.STRING, null, _("Remove an item from dock"), _("ITEM") },
                { "describe", 0, 0, OptionArg.NONE, null, _("Print configuration and parameter metadata as JSON"), null },
                { null }
            };
            add_main_option_entries (options);
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

            if (options.contains ("describe")) {
                cmdline.print ("%s", describe_json (config));
                return 0;
            }

            activate ();

            string item;
            if (options.lookup ("add-item", "s", out item)) {
                add_dock_item (item);
                return 0;
            }

            if (options.lookup ("remove-item", "s", out item)) {
                remove_dock_item (item);
                return 0;
            }

            return 0;
        }

        protected override void activate () {
            if (activated) return;
            activated = true;

            create_configured_docks ();

            setup_autohide ();

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

        }

        private void create_dock_for_monitor (Gdk.Monitor monitor) {
            var dock = new DockWindow (this, monitor);
            dock.grid_requested.connect (() => {
                toggle_grid ();
            });
            add_window (dock);
            dock_windows.add (dock);
        }

        public static string monitor_id (Gdk.Monitor monitor, uint index) {
            var connector = monitor.get_connector ();
            if (connector != null && connector.length > 0) return connector;
            return "monitor-%u".printf (index);
        }

        private void create_configured_docks () {
            var monitors = Gdk.Display.get_default ().get_monitors ();
            for (uint i = 0; i < monitors.get_n_items (); i++) {
                var monitor = (Gdk.Monitor) monitors.get_item (i);
                if (config.is_monitor_enabled (monitor_id (monitor, i))) {
                    create_dock_for_monitor (monitor);
                }
            }
        }

        public void apply_monitor_selection () {
            // A layer-shell surface cannot be moved safely between outputs;
            // recreating the selected surfaces also keeps their exclusive
            // zones and autohide hotspots consistent.
            for (uint i = 0; i < dock_triggers.length; i++) {
                remove_window (dock_triggers[i]);
                dock_triggers[i].destroy ();
            }
            for (uint i = 0; i < dock_windows.length; i++) {
                remove_window (dock_windows[i]);
                dock_windows[i].destroy ();
            }
            dock_triggers = new GenericArray<DockTrigger> ();
            dock_windows = new GenericArray<DockWindow> ();
            create_configured_docks ();
            setup_autohide ();
            // Newly created surfaces need the already-cached window state;
            // waiting for the next compositor event leaves their indicators
            // empty until a workspace change.
            for (uint i = 0; i < dock_windows.length; i++) {
                dock_windows[i].update_indicators ();
            }
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

        public void add_dock_item (string item) {
            if (!ConfigManager.is_app_item (item) && !ConfigManager.is_folder_item (item))
                return;
            if (config.has_dock_item (item)) return;
            config.add_dock_item (item);
            config.save ();
            rebuild_docks ();
        }

        public void remove_dock_item (string item) {
            if (!config.has_dock_item (item)) return;
            config.remove_dock_item (item);
            config.save ();
            rebuild_docks ();
        }

        public void remove_dock_folder (string folder_path) {
            config.remove_folder (folder_path);
            config.save ();
            rebuild_docks ();
        }

        public void add_dock_folder (string folder_path) {
            if (!FileUtils.test (folder_path, FileTest.IS_DIR) ||
                config.find_folder (folder_path) != null) return;
            config.add_folder (folder_path);
            config.save ();
            rebuild_docks ();
        }

        public void add_dock_folder_at (string folder_path, int position) {
            if (!FileUtils.test (folder_path, FileTest.IS_DIR) ||
                config.find_folder (folder_path) != null) return;
            config.add_folder_at (folder_path, position);
            config.save ();
            rebuild_docks ();
        }

        public void reorder_dock_folder (string folder_path, int position) {
            config.reorder_folder (folder_path, position);
            config.save ();
            rebuild_docks ();
        }

        public void reorder_dock_item (string item, int position) {
            config.reorder_dock_item (item, position);
            config.save ();
            rebuild_docks ();
        }

        private void rebuild_docks () {
            for (uint i = 0; i < dock_windows.length; i++) {
                dock_windows[i].rebuild_dock ();
            }
        }

        private void setup_autohide () {
            // A pinned dock reserves screen space and remains visible;
            // the floating mode always uses the edge trigger and autohide.
            bool should_autohide = config.dock_mode == DockMode.FLOATING;
            if (should_autohide) {
                if (dock_triggers.length == 0) {
                    for (uint i = 0; i < dock_windows.length; i++) {
                        var dock = dock_windows[i];
                        var trigger = new DockTrigger (this, dock.monitor);
                        trigger.trigger_activated.connect (() => {
                            dock.reveal_from_trigger ();
                        });
                        dock.set_trigger (trigger);
                        add_window (trigger);
                        dock_triggers.add (trigger);
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
