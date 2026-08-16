namespace XimperShellDock {

    // A non-modal layer-shell surface for a folder stack. Unlike an
    // autohiding Gtk.Popover it does not take a Wayland input grab, so drag
    // sources inside the folder can target external applications.
    public class FolderStackWindow : Gtk.Window {

        private FolderDockIcon? current_folder = null;
        private bool open = false;
        // Gtk.Popover temporarily makes this layer-shell surface inactive
        // while it takes focus. That is still interaction with the stack,
        // not a request to dismiss it.
        private bool embedded_popover_open = false;
        private DockPosition position = DockPosition.BOTTOM;

        public signal void state_changed (bool open);

        public FolderStackWindow (Gdk.Monitor? monitor) {
            title = "Ximper Shell Folder Stack";
            decorated = false;
            resizable = false;
            add_css_class ("folder-stack-window");

            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
            apply_position (DockPosition.BOTTOM);
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
        }

        public void apply_position (DockPosition value) {
            if (open && position != value) close_stack ();
            position = value;
            GtkLayerShell.Edge[] edges = { GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                                           GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT };
            foreach (var edge in edges) {
                GtkLayerShell.set_anchor (this, edge, false);
                GtkLayerShell.set_margin (this, edge, 0);
            }
            if (position == DockPosition.BOTTOM) {
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
            } else {
                GtkLayerShell.set_anchor (this, position == DockPosition.LEFT
                    ? GtkLayerShell.Edge.LEFT : GtkLayerShell.Edge.RIGHT, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
            }
        }

        public void present_folder (FolderDockIcon folder, int along, int edge_margin) {
            if (open && current_folder == folder) {
                close_stack ();
                return;
            }

            current_folder = folder;
            if (position == DockPosition.BOTTOM) {
                GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, along);
                GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, edge_margin);
            } else {
                GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, along);
                GtkLayerShell.set_margin (this, position == DockPosition.LEFT
                    ? GtkLayerShell.Edge.LEFT : GtkLayerShell.Edge.RIGHT, edge_margin);
            }
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
            embedded_popover_open = false;
            state_changed (false);
        }

        public void refresh_folder (FolderDockIcon folder) {
            if (!open || current_folder != folder) return;
            set_child (folder.create_stack_content (this));
        }

        public void set_embedded_popover_open (bool value) {
            embedded_popover_open = value;
            if (value) return;

            // A layer-shell surface is not guaranteed to become active when
            // shown.  Closing here would make the stack disappear immediately
            // on compositors that keep focus on the dock or another window.
        }

    }
}
