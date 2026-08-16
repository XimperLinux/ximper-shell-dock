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
        private Gdk.Monitor? monitor;
        private int content_max_width = int.MAX;
        private int content_max_height = int.MAX;

        public signal void state_changed (bool open);

        public FolderStackWindow (Gdk.Monitor? monitor) {
            this.monitor = monitor;
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
            switch (position) {
                case DockPosition.TOP:
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                    break;
                case DockPosition.LEFT:
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                    break;
                case DockPosition.RIGHT:
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                    break;
                default:
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
                    GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                    break;
            }
        }

        public void present_folder (FolderDockIcon folder, int along, int edge_margin) {
            if (open && current_folder == folder) {
                close_stack ();
                return;
            }

            current_folder = folder;
            switch (position) {
                case DockPosition.TOP:
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, along);
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, edge_margin);
                    break;
                case DockPosition.LEFT:
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, along);
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, edge_margin);
                    break;
                case DockPosition.RIGHT:
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, along);
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, edge_margin);
                    break;
                default:
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, along);
                    GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, edge_margin);
                    break;
            }
            int max_width;
            int max_height;
            get_available_size (along, edge_margin, out max_width, out max_height);
            content_max_width = max_width;
            content_max_height = max_height;
            set_child (folder.create_stack_content (this, max_width, max_height));
            set_default_size (int.min (folder.get_stack_width (), max_width),
                              int.min (folder.get_stack_height (), max_height));
            if (!open) {
                open = true;
                state_changed (true);
            }
            present ();
        }

        private void get_available_size (int along, int edge_margin,
                                         out int width, out int height) {
            width = int.MAX;
            height = int.MAX;
            if (monitor == null) return;

            var geometry = monitor.geometry;
            if (position.is_vertical ()) {
                // The stack is anchored at the top and offset by `along`.
                // Limit its height to the remaining monitor area.
                width = int.max (geometry.width - edge_margin, 1);
                height = int.max (geometry.height - along, 1);
            } else {
                width = int.max (geometry.width - along, 1);
                height = int.max (geometry.height - edge_margin, 1);
            }
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
            set_child (folder.create_stack_content (this, content_max_width,
                                                    content_max_height));
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
