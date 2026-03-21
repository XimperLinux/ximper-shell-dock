namespace XimperShellDock {

    public class RunningApp {
        public string app_class;
        public int pid;
        public string title;

        public RunningApp (string app_class, int pid, string title) {
            this.app_class = app_class;
            this.pid = pid;
            this.title = title;
        }
    }

    public class WindowTracker : Object {

        public GenericArray<RunningApp> running_apps;
        public string? focused_class { get; private set; default = null; }

        private IOChannel? event_channel;
        private uint event_source_id = 0;

        public signal void windows_changed ();

        public WindowTracker () {
            running_apps = new GenericArray<RunningApp> ();
        }

        public void start () {
            refresh_clients ();
            connect_event_socket ();
        }

        public void stop () {
            if (event_source_id != 0) {
                Source.remove (event_source_id);
                event_source_id = 0;
            }
            if (event_channel != null) {
                try { event_channel.shutdown (false); } catch (Error e) {}
                event_channel = null;
            }
        }

        public bool is_running (string desktop_id) {
            if (running_apps == null) return false;
            var app_id = desktop_id.replace (".desktop", "");
            for (uint i = 0; i < running_apps.length; i++) {
                if (match_class (running_apps[i].app_class, app_id)) return true;
            }
            return false;
        }

        public bool is_focused (string desktop_id) {
            if (focused_class == null) return false;
            var app_id = desktop_id.replace (".desktop", "");
            return match_class (focused_class, app_id);
        }

        private bool match_class (string window_class, string app_id) {
            if (window_class == app_id) return true;
            if (window_class.down () == app_id.down ()) return true;
            var parts = app_id.split (".");
            if (parts.length > 0 &&
                window_class.down () == parts[parts.length - 1].down ()) return true;
            return false;
        }

        private void connect_event_socket () {
            var sig = Environment.get_variable ("HYPRLAND_INSTANCE_SIGNATURE");
            if (sig == null) {
                warning ("HYPRLAND_INSTANCE_SIGNATURE not set, falling back to polling");
                start_polling ();
                return;
            }

            var runtime_dir = Environment.get_variable ("XDG_RUNTIME_DIR");
            if (runtime_dir == null) {
                warning ("XDG_RUNTIME_DIR not set");
                start_polling ();
                return;
            }
            var socket_path = Path.build_filename (runtime_dir, "hypr", sig, ".socket2.sock");

            if (!FileUtils.test (socket_path, FileTest.EXISTS)) {
                warning ("Hyprland event socket not found: %s", socket_path);
                start_polling ();
                return;
            }

            try {
                var socket = new Socket (SocketFamily.UNIX, SocketType.STREAM, SocketProtocol.DEFAULT);
                var addr = new UnixSocketAddress (socket_path);
                socket.connect (addr);
                socket.set_blocking (false);

                var fd = socket.get_fd ();
                event_channel = new IOChannel.unix_new (fd);
                event_channel.set_encoding (null);
                event_channel.set_flags (IOFlags.NONBLOCK);

                event_source_id = event_channel.add_watch (
                    IOCondition.IN | IOCondition.HUP,
                    on_event_data
                );

                // Keep socket alive by preventing GC
                socket.ref ();
            } catch (Error e) {
                warning ("Failed to connect to Hyprland event socket: %s", e.message);
                start_polling ();
            }
        }

        private bool on_event_data (IOChannel source, IOCondition condition) {
            if ((condition & IOCondition.HUP) != 0) {
                warning ("Hyprland event socket closed");
                return false;
            }

            try {
                string line;
                size_t length;
                IOStatus status;

                while ((status = source.read_line (out line, out length, null)) == IOStatus.NORMAL) {
                    if (line == null) break;
                    handle_event (line.strip ());
                }
            } catch (Error e) {
                // EAGAIN is expected for non-blocking
            }

            return true;
        }

        private void handle_event (string event_line) {
            // Events: openwindow, closewindow, activewindow, movewindow, etc.
            if (event_line.has_prefix ("openwindow>>") ||
                event_line.has_prefix ("closewindow>>") ||
                event_line.has_prefix ("movewindow>>")) {
                refresh_clients ();
            } else if (event_line.has_prefix ("activewindowv2>>") ||
                       event_line.has_prefix ("activewindow>>")) {
                // activewindow>>CLASS,TITLE
                if (event_line.has_prefix ("activewindow>>")) {
                    var data = event_line.substring ("activewindow>>".length);
                    var parts = data.split (",", 2);
                    if (parts.length >= 1) {
                        focused_class = parts[0];
                        windows_changed ();
                    }
                }
            }
        }

        private void refresh_clients () {
            try {
                string stdout_buf;
                int exit_status;

                Process.spawn_command_line_sync (
                    "hyprctl clients -j",
                    out stdout_buf, null, out exit_status
                );

                if (exit_status != 0 || stdout_buf == null) return;

                running_apps = new GenericArray<RunningApp> ();

                var parser = new Json.Parser ();
                parser.load_from_data (stdout_buf);

                var array = parser.get_root ().get_array ();
                array.foreach_element ((arr, idx, node) => {
                    var obj = node.get_object ();
                    var app_class = obj.get_string_member ("class");
                    var pid = (int) obj.get_int_member ("pid");
                    var title = obj.get_string_member ("title");

                    if (app_class != null && app_class.length > 0) {
                        running_apps.add (new RunningApp (app_class, pid, title));
                    }
                });

                // Get focused
                Process.spawn_command_line_sync (
                    "hyprctl activewindow -j",
                    out stdout_buf, null, out exit_status
                );
                if (exit_status == 0 && stdout_buf != null && stdout_buf.length > 2) {
                    var ap = new Json.Parser ();
                    ap.load_from_data (stdout_buf);
                    focused_class = ap.get_root ().get_object ().get_string_member ("class");
                }

                windows_changed ();
            } catch (Error e) {
                // ignore
            }
        }

        // Fallback for non-Hyprland compositors
        private void start_polling () {
            Timeout.add (2000, () => {
                refresh_clients ();
                return Source.CONTINUE;
            });
        }
    }
}
