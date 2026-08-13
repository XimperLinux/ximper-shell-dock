namespace XimperShellDock {

    public class NiriHelper : CompositorHelper {

        public override string name { owned get { return "Niri"; } }

        private IOChannel? event_channel;
        private uint event_source_id = 0;
        private uint child_watch_id = 0;
        private Pid event_pid = 0;
        private bool refresh_pending = false;

        public static bool is_available () {
            var socket = Environment.get_variable ("NIRI_SOCKET");
            return socket != null && socket.length > 0 && FileUtils.test (socket, FileTest.EXISTS);
        }

        public override void start () {
            refresh_clients ();
            connect_event_stream ();
        }

        public override void stop () {
            stop_polling ();
            if (event_source_id != 0) {
                Source.remove (event_source_id);
                event_source_id = 0;
            }
            if (child_watch_id != 0 && event_pid == 0) {
                Source.remove (child_watch_id);
                child_watch_id = 0;
            }
            if (event_channel != null) {
                try { event_channel.shutdown (false); } catch (Error e) {}
                event_channel = null;
            }
            if (event_pid != 0) {
                Posix.kill (event_pid, Posix.Signal.TERM);
                event_pid = 0;
            }
        }

        protected override void focus_running_app (RunningApp running) {
            if (running.window_id == null) return;

            try {
                Process.spawn_command_line_async (
                    "niri msg action focus-window --id " + Shell.quote (running.window_id)
                );
            } catch (Error e) {
                warning ("Failed to focus Niri window: %s", e.message);
            }
        }

        protected override void close_running_app (RunningApp running) {
            if (running.window_id == null) return;

            try {
                Process.spawn_command_line_async (
                    "niri msg action close-window --id " + Shell.quote (running.window_id)
                );
            } catch (Error e) {
                warning ("Failed to close Niri window: %s", e.message);
            }
        }

        private void connect_event_stream () {
            try {
                string[] argv = { "niri", "msg", "--json", "event-stream" };
                int stdout_fd;
                int stderr_fd;

                Process.spawn_async_with_pipes (
                    null, argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    null,
                    out event_pid,
                    null,
                    out stdout_fd,
                    out stderr_fd
                );

                Posix.close (stderr_fd);
                child_watch_id = ChildWatch.add (event_pid, (pid, status) => {
                    Process.close_pid (pid);
                    if (event_pid == pid) event_pid = 0;
                    child_watch_id = 0;
                });

                event_channel = new IOChannel.unix_new (stdout_fd);
                event_channel.set_encoding (null);
                event_channel.set_flags (IOFlags.NONBLOCK);

                event_source_id = event_channel.add_watch (
                    IOCondition.IN | IOCondition.HUP,
                    on_event_data
                );
            } catch (Error e) {
                warning ("Failed to start Niri event stream: %s", e.message);
                start_polling ();
            }
        }

        private bool on_event_data (IOChannel source, IOCondition condition) {
            if ((condition & IOCondition.HUP) != 0) {
                warning ("Niri event stream closed");
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
                // EAGAIN is expected for non-blocking pipes.
            }

            return true;
        }

        private void handle_event (string event_line) {
            if (event_line.length == 0) return;
            schedule_refresh ();
        }

        private void schedule_refresh () {
            if (refresh_pending) return;
            refresh_pending = true;
            Idle.add (() => {
                refresh_pending = false;
                refresh_clients ();
                return Source.REMOVE;
            });
        }

        public override void refresh_clients () {
            try {
                string stdout_buf;
                int exit_status;

                Process.spawn_command_line_sync (
                    "niri msg --json windows",
                    out stdout_buf, null, out exit_status
                );

                if (exit_status != 0 || stdout_buf == null) return;

                running_apps = new GenericArray<RunningApp> ();
                focused_class = null;

                var parser = new Json.Parser ();
                parser.load_from_data (stdout_buf);

                var array = parser.get_root ().get_array ();
                array.foreach_element ((arr, idx, node) => {
                    var obj = node.get_object ();
                    if (!obj.has_member ("app_id")) return;
                    if (obj.get_member ("app_id").get_node_type () == Json.NodeType.NULL) return;

                    var app_id = obj.get_string_member ("app_id");
                    if (app_id == null || app_id.length == 0) return;

                    var pid = 0;
                    if (obj.has_member ("pid") &&
                        obj.get_member ("pid").get_node_type () != Json.NodeType.NULL) {
                        pid = (int) obj.get_int_member ("pid");
                    }

                    var title = "";
                    if (obj.has_member ("title") &&
                        obj.get_member ("title").get_node_type () != Json.NodeType.NULL) {
                        title = obj.get_string_member ("title");
                    }

                    var window_id = obj.has_member ("id") ? obj.get_int_member ("id").to_string () : null;
                    running_apps.add (new RunningApp (app_id, pid, title, window_id));

                    if (obj.has_member ("is_focused") && obj.get_boolean_member ("is_focused")) {
                        focused_class = app_id;
                    }
                });

                notify_windows_changed ();
            } catch (Error e) {
                // Niri may be absent, restarting, or returning newer JSON than we understand.
            }
        }
    }
}
