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

        public bool is_running_app (AppEntry entry) {
            return helper.is_running_app (entry);
        }

        public bool is_focused_app (AppEntry entry) {
            return helper.is_focused_app (entry);
        }

        public void focus_app (AppEntry entry) {
            helper.focus_app (entry);
        }

        public void focus_window (RunningApp running) {
            helper.focus_window (running);
        }

        public GenericArray<RunningApp> windows_for_app (AppEntry entry) {
            return helper.windows_for_app (entry);
        }

        public void close_app (AppEntry entry) {
            helper.close_app_entry (entry);
        }
    }
}
