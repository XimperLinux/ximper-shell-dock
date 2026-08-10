namespace XimperShellDock {

    // A non-modal layer-shell surface for a folder stack. Unlike an
    // autohiding Gtk.Popover it does not take a Wayland input grab, so drag
    // sources inside the folder can target external applications.
    public class FolderStackWindow : Gtk.Window {

        private FolderDockIcon? current_folder = null;
        private bool open = false;

        public signal void state_changed (bool open);

        public FolderStackWindow (Gdk.Monitor? monitor) {
            title = "Ximper Shell Folder Stack";
            decorated = false;
            resizable = false;
            add_css_class ("folder-stack-window");

            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, false);
            GtkLayerShell.set_exclusive_zone (this, -1);
            GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.ON_DEMAND);
            GtkLayerShell.set_namespace (this, "ximper-shell-dock-folder-stack");
            if (monitor != null) GtkLayerShell.set_monitor (this, monitor);

            var key = new Gtk.EventControllerKey ();
            key.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    close_stack ();
                    return true;
                }
                return false;
            });
            ((Gtk.Widget) this).add_controller (key);
            close_request.connect (() => {
                close_stack ();
                return true;
            });
            notify["is-active"].connect (() => {
                // The layer surface remains non-modal for external DnD, but
                // should not linger after the user activates another window.
                if (open && !is_active) close_stack ();
            });
        }

        public void present_folder (FolderDockIcon folder, int left, int bottom) {
            if (open && current_folder == folder) {
                close_stack ();
                return;
            }

            current_folder = folder;
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, left);
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, bottom);
            set_child (folder.create_stack_content (this));
            set_default_size (folder.get_stack_width (), folder.get_stack_height ());
            if (!open) {
                open = true;
                state_changed (true);
            }
            present ();
        }

        public void close_stack () {
            if (!open) return;
            hide ();
            current_folder = null;
            open = false;
            state_changed (false);
        }
    }
}
