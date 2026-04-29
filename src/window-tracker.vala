namespace XimperShellDock {

    public class WindowTracker : Object {

        public GenericArray<RunningApp> running_apps {
            get { return helper.running_apps; }
        }
        public string? focused_class {
            get { return helper.focused_class; }
        }

        private CompositorHelper helper;

        public signal void windows_changed ();

        public WindowTracker () {
            if (NiriHelper.is_available ()) {
                helper = new NiriHelper ();
            } else {
                helper = new HyprlandHelper ();
            }

            helper.windows_changed.connect (() => {
                windows_changed ();
            });

            message ("Using %s window helper", helper.name);
        }

        public void start () {
            helper.start ();
        }

        public void stop () {
            helper.stop ();
        }

        public bool is_running (string desktop_id) {
            return helper.is_running (desktop_id);
        }

        public bool is_focused (string desktop_id) {
            return helper.is_focused (desktop_id);
        }

        public bool matches_desktop_id (string window_class, string desktop_id) {
            return helper.matches_desktop_id (window_class, desktop_id);
        }

        public void focus_window (string desktop_id) {
            helper.focus_window (desktop_id);
        }

        public void close_app (string desktop_id) {
            helper.close_app (desktop_id);
        }
    }
}
