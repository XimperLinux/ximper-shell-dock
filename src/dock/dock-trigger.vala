namespace XimperShellDock {

    public class DockTrigger : Gtk.Window {

        public signal void trigger_activated ();
        public bool cursor_on_trigger { get; private set; default = false; }
        public Gdk.Monitor? monitor { get; private set; }
        private Gtk.DrawingArea hotspot;
        private DockPosition position;
        private int edge_margin = 4;

        public DockTrigger (Application app, Gdk.Monitor? monitor = null,
                            int edge_margin = 4, DockPosition position = DockPosition.BOTTOM) {
            this.title = "Ximper Shell Dock Trigger";
            this.decorated = false;
            this.monitor = monitor;
            this.position = position;

            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_exclusive_zone (this, 0);
            GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
            GtkLayerShell.set_namespace (this, "ximper-shell-dock-hotspot");

            if (monitor != null) {
                GtkLayerShell.set_monitor (this, monitor);
            }

            apply_position (position);

            // Remove adwaita window background, our DrawingArea handles rendering
            remove_css_class ("background");

            // DrawingArea draws near-invisible content to keep Wayland surface alive for input
            hotspot = new Gtk.DrawingArea ();
            set_edge_margin (edge_margin);
            hotspot.set_draw_func ((area, cr, w, h) => {
                cr.set_source_rgba (0, 0, 0, 0.004);
                cr.set_operator (Cairo.Operator.SOURCE);
                cr.paint ();
            });

            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect ((x, y) => {
                cursor_on_trigger = true;
                trigger_activated ();
            });
            motion.leave.connect (() => {
                cursor_on_trigger = false;
            });
            ((Gtk.Widget) hotspot).add_controller (motion);

            var click = new Gtk.GestureClick ();
            click.pressed.connect ((n, x, y) => {
                trigger_activated ();
            });
            ((Gtk.Widget) hotspot).add_controller (click);

            // Pointer motion alone is not delivered while a file-manager
            // drag is in progress. Accept directory drags on the edge
            // hotspot so the autohidden dock opens before the actual drop.
            var file_drag = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            file_drag.motion.connect ((x, y) => {
                cursor_on_trigger = true;
                trigger_activated ();
                return Gdk.DragAction.COPY;
            });
            file_drag.leave.connect (() => {
                cursor_on_trigger = false;
            });
            file_drag.drop.connect ((value, x, y) => {
                // The dock surface receives the final drop after it is shown.
                return false;
            });
            ((Gtk.Widget) hotspot).add_controller (file_drag);

            set_child (hotspot);
        }

        public void set_edge_margin (int edge_margin) {
            this.edge_margin = edge_margin;
            int size = int.max (edge_margin, 4);
            hotspot.set_size_request (position.is_vertical () ? size : -1,
                                      position.is_vertical () ? -1 : size);
        }

        public void apply_position (DockPosition value) {
            position = value;
            GtkLayerShell.Edge[] edges = { GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                                           GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT };
            foreach (var edge in edges) GtkLayerShell.set_anchor (this, edge, false);
            if (!position.is_vertical ()) {
                GtkLayerShell.set_anchor (this, position == DockPosition.TOP
                    ? GtkLayerShell.Edge.TOP : GtkLayerShell.Edge.BOTTOM, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.LEFT, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
            } else {
                GtkLayerShell.set_anchor (this, position == DockPosition.LEFT
                    ? GtkLayerShell.Edge.LEFT : GtkLayerShell.Edge.RIGHT, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
                GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.BOTTOM, true);
            }
            if (hotspot != null) set_edge_margin (edge_margin);
        }
    }
}
