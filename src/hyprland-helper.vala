namespace XimperShellDock {

    public class HyprlandHelper : CompositorHelper {

        public override string name { owned get { return "Hyprland"; } }

        private IOChannel? event_channel;
        private uint event_source_id = 0;
        private Socket? event_socket;
        private bool? lua_dispatch_supported = null;

        public override void start () {
            refresh_clients ();
            connect_event_socket ();
        }

        public override void stop () {
            stop_polling ();
            if (event_source_id != 0) {
                Source.remove (event_source_id);
                event_source_id = 0;
            }
            if (event_channel != null) {
                try { event_channel.shutdown (false); } catch (Error e) {}
                event_channel = null;
            }
            event_socket = null;
        }

        protected override void focus_running_app (RunningApp running) {
            try {
                var selector = running.window_id != null && running.window_id.length > 0
                    ? "address:" + running.window_id : "class:" + running.app_class;
                var command = lua_dispatch_is_supported ()
                    ? "hyprctl dispatch " + Shell.quote (
                        "hl.dsp.focus({ window = \"" + selector + "\" })"
                    )
                    : "hyprctl dispatch focuswindow " + Shell.quote (selector);
                Process.spawn_command_line_async (command);
            } catch (Error e) {
                warning ("Failed to focus Hyprland window: %s", e.message);
            }
        }

        protected override void close_running_app (RunningApp running) {
            try {
                var selector = running.window_id != null && running.window_id.length > 0
                    ? "address:" + running.window_id : "class:" + running.app_class;
                var command = lua_dispatch_is_supported ()
                    ? "hyprctl dispatch " + Shell.quote (
                        "hl.dsp.window.close({ window = \"" + selector + "\" })"
                    )
                    : "hyprctl dispatch closewindow " + Shell.quote (selector);
                Process.spawn_command_line_async (command);
            } catch (Error e) {
                warning ("Failed to close Hyprland window: %s", e.message);
            }
        }

        private bool lua_dispatch_is_supported () {
            if (lua_dispatch_supported != null) return lua_dispatch_supported;

            lua_dispatch_supported = false;
            try {
                string stdout_buf;
                int exit_status;
                Process.spawn_command_line_sync (
                    "hyprctl version",
                    out stdout_buf, null, out exit_status
                );
                if (exit_status != 0 || stdout_buf == null) return false;

                var regex = new Regex ("([0-9]+)\\.([0-9]+)");
                MatchInfo match_info;
                if (regex.match (stdout_buf, 0, out match_info)) {
                    int major = int.parse (match_info.fetch (1));
                    int minor = int.parse (match_info.fetch (2));
                    lua_dispatch_supported = major > 0 || minor >= 55;
                }
            } catch (Error e) {
                warning ("Cannot determine Hyprland version: %s", e.message);
            }
            return lua_dispatch_supported;
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
                event_socket = new Socket (SocketFamily.UNIX, SocketType.STREAM, SocketProtocol.DEFAULT);
                var addr = new UnixSocketAddress (socket_path);
                event_socket.connect (addr);
                event_socket.set_blocking (false);

                var fd = event_socket.get_fd ();
                event_channel = new IOChannel.unix_new (fd);
                event_channel.set_encoding (null);
                event_channel.set_flags (IOFlags.NONBLOCK);

                event_source_id = event_channel.add_watch (
                    IOCondition.IN | IOCondition.HUP,
                    on_event_data
                );
            } catch (Error e) {
                warning ("Failed to connect to Hyprland event socket: %s", e.message);
                event_socket = null;
                start_polling ();
            }
        }

        private bool on_event_data (IOChannel source, IOCondition condition) {
            if ((condition & IOCondition.HUP) != 0) {
                warning ("Hyprland event socket closed");
                event_source_id = 0;
                start_polling ();
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
                // EAGAIN is expected for non-blocking sockets.
            }

            return true;
        }

        private void handle_event (string event_line) {
            if (event_line.has_prefix ("openwindow>>") ||
                event_line.has_prefix ("closewindow>>") ||
                event_line.has_prefix ("movewindow>>")) {
                refresh_clients ();
            } else if (event_line.has_prefix ("activewindow>>")) {
                var data = event_line.substring ("activewindow>>".length);
                var parts = data.split (",", 2);
                if (parts.length >= 1) {
                    focused_class = parts[0];
                    notify_windows_changed ();
                }
            } else if (event_line.has_prefix ("activewindowv2>>")) {
                refresh_clients ();
            }
        }

        public override void refresh_clients () {
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
                    if (!obj.has_member ("class")) return;
                    var app_class = obj.get_string_member ("class");
                    if (app_class == null || app_class.length == 0) return;
                    var pid = obj.has_member ("pid") ? (int) obj.get_int_member ("pid") : 0;
                    var title = obj.has_member ("title") ? obj.get_string_member ("title") : "";
                    var address = obj.has_member ("address") ? obj.get_string_member ("address") : null;

                    running_apps.add (new RunningApp (app_class, pid, title, address));
                });

                Process.spawn_command_line_sync (
                    "hyprctl activewindow -j",
                    out stdout_buf, null, out exit_status
                );
                if (exit_status == 0 && stdout_buf != null && stdout_buf.length > 2) {
                    var ap = new Json.Parser ();
                    ap.load_from_data (stdout_buf);
                    var fobj = ap.get_root ().get_object ();
                    if (fobj.has_member ("class"))
                        focused_class = fobj.get_string_member ("class");
                }

                notify_windows_changed ();
            } catch (Error e) {
                // Hyprland can briefly return incomplete JSON while restarting.
            }
        }
    }
}
