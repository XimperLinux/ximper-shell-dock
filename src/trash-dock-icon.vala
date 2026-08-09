namespace XimperShellDock {

    // A system item, deliberately kept outside ConfigManager.dock_items so it
    // cannot be reordered with, or accidentally removed as, a pinned app.
    public class TrashDockIcon : Gtk.Box {

        private Gtk.Button button;
        private Gtk.Image image;
        private int icon_size;
        private double magnification = 1.0;
        private double horizontal_offset = 0.0;

        public signal void drag_state_changed (bool active);

        public TrashDockIcon (int icon_size) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.icon_size = icon_size;
            halign = Gtk.Align.CENTER;

            button = new Gtk.Button ();
            button.focusable = false;
            button.add_css_class ("dock-icon");
            button.add_css_class ("flat");
            button.add_css_class ("dock-trash-icon");
            button.tooltip_text = "Trash";

            image = new Gtk.Image.from_icon_name ("user-trash-symbolic");
            image.pixel_size = icon_size;
            button.set_child (image);
            button.clicked.connect (() => { open_trash (); });
            append (button);

            var indicator_space = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            indicator_space.add_css_class ("dock-indicator-box");
            append (indicator_space);

            setup_file_drop_target ();
        }

        public void update_icon_size (int size) {
            icon_size = size;
            image.pixel_size = size;
        }

        public void set_visual_state (double scale, double offset) {
            if (magnification == scale && horizontal_offset == offset) return;
            magnification = scale;
            horizontal_offset = offset;
            queue_draw ();
        }

        protected override void snapshot (Gtk.Snapshot snapshot) {
            if (magnification == 1.0 && horizontal_offset == 0.0) {
                base.snapshot (snapshot);
                return;
            }
            float scale = (float) magnification;
            var offset = Graphene.Point ();
            offset.init ((float) horizontal_offset + (get_width () * (1.0f - scale)) / 2.0f,
                         get_height () * (1.0f - scale));
            snapshot.save ();
            snapshot.translate (offset);
            snapshot.scale (scale, scale);
            base.snapshot (snapshot);
            snapshot.restore ();
        }

        private void setup_file_drop_target () {
            var target = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.MOVE);
            target.enter.connect ((x, y) => {
                button.add_css_class ("dock-trash-drop-active");
                drag_state_changed (true);
                return Gdk.DragAction.MOVE;
            });
            target.leave.connect (() => {
                button.remove_css_class ("dock-trash-drop-active");
                drag_state_changed (false);
            });
            target.drop.connect ((value, x, y) => {
                button.remove_css_class ("dock-trash-drop-active");
                drag_state_changed (false);
                var files = (Gdk.FileList) value;
                bool moved = false;
                foreach (var file in files.get_files ()) {
                    try {
                        file.trash (null);
                        moved = true;
                    } catch (Error e) {
                        warning ("Failed to move '%s' to Trash: %s", file.get_uri (), e.message);
                    }
                }
                return moved;
            });
            button.add_controller (target);
        }

        private void open_trash () {
            try {
                AppInfo.launch_default_for_uri ("trash:///", null);
            } catch (Error e) {
                warning ("Failed to open Trash: %s", e.message);
            }
        }
    }
}
