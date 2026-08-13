namespace XimperShellDock {

    public class RunningApp {
        public string app_class;
        public int pid;
        public string title;
        public string? window_id;

        public RunningApp (string app_class, int pid, string title, string? window_id = null) {
            this.app_class = app_class;
            this.pid = pid;
            this.title = title;
            this.window_id = window_id;
        }
    }

    public abstract class CompositorHelper : Object {
        public GenericArray<RunningApp> running_apps;
        public string? focused_class { get; protected set; default = null; }

        private uint polling_source_id = 0;

        public signal void windows_changed ();

        protected CompositorHelper () {
            running_apps = new GenericArray<RunningApp> ();
        }

        public abstract string name { owned get; }
        public abstract void start ();
        public abstract void stop ();
        public abstract void refresh_clients ();
        protected abstract void focus_running_app (RunningApp running);
        protected abstract void close_running_app (RunningApp running);

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

        public bool matches_desktop_id (string window_class, string desktop_id) {
            var app_id = desktop_id.replace (".desktop", "");
            return match_class (window_class, app_id);
        }

        protected bool match_class (string window_class, string app_id) {
            if (window_class == app_id) return true;
            if (window_class.down () == app_id.down ()) return true;
            var parts = app_id.split (".");
            if (parts.length > 0 &&
                window_class.down () == parts[parts.length - 1].down ()) return true;
            return false;
        }

        public bool is_running_app (AppEntry entry) {
            return find_running_app (entry) != null;
        }

        public bool is_focused_app (AppEntry entry) {
            return focused_class != null && entry.matches_window_class (focused_class);
        }

        public void focus_app (AppEntry entry) {
            var running = find_running_app (entry);
            if (running != null) focus_running_app (running);
        }

        public void close_app_entry (AppEntry entry) {
            var running = find_running_app (entry);
            if (running != null) close_running_app (running);
        }

        private RunningApp? find_running_app (AppEntry entry) {
            for (uint i = 0; i < running_apps.length; i++) {
                if (entry.matches_window_class (running_apps[i].app_class)) return running_apps[i];
            }
            return null;
        }

        protected void notify_windows_changed () {
            windows_changed ();
        }

        protected void start_polling () {
            stop_polling ();
            polling_source_id = Timeout.add (2000, () => {
                refresh_clients ();
                return Source.CONTINUE;
            });
        }

        protected void stop_polling () {
            if (polling_source_id != 0) {
                Source.remove (polling_source_id);
                polling_source_id = 0;
            }
        }
    }
}
