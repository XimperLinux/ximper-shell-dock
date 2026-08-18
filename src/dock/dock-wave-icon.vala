namespace XimperShellDock {

    private class GridWaveIcon : Gtk.Box {
        private double magnification = 1.0;
        private double horizontal_offset = 0.0;
        private Gtk.Button? input_button;
        private DockPosition dock_position = DockPosition.BOTTOM;

        public GridWaveIcon (DockPosition position = DockPosition.BOTTOM) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            halign = Gtk.Align.CENTER;
            apply_position (position);
        }

        public void apply_position (DockPosition position) {
            dock_position = position;
            orientation = position.is_vertical () ? Gtk.Orientation.HORIZONTAL
                                                   : Gtk.Orientation.VERTICAL;
            queue_draw ();
        }

        public void set_visual_state (double scale, double offset) {
            if (magnification == scale && horizontal_offset == offset) return;
            magnification = scale;
            horizontal_offset = offset;
            queue_draw ();
        }

        public void set_input_button (Gtk.Button button) {
            input_button = button;
        }

        public void activate_button () {
            if (input_button != null) input_button.activate ();
        }

        public void set_magnified_hover (bool hovered) {
            if (input_button == null) return;
            if (hovered) input_button.add_css_class ("dock-icon-magnified-hover");
            else input_button.remove_css_class ("dock-icon-magnified-hover");
        }

        protected override void snapshot (Gtk.Snapshot snapshot) {
            if (magnification == 1.0 && horizontal_offset == 0.0) {
                base.snapshot (snapshot);
                return;
            }
            float scale = (float) magnification;
            var offset = Graphene.Point ();
            if (!dock_position.is_vertical())
                offset.init ((float) horizontal_offset + (get_width () * (1.0f - scale)) / 2.0f,
                             dock_position == DockPosition.TOP ? 0.0f : get_height () * (1.0f - scale));
            else
                offset.init (dock_position == DockPosition.LEFT ? 0.0f
                            : get_width () * (1.0f - scale),
                             (float) horizontal_offset + (get_height () * (1.0f - scale)) / 2.0f);
            snapshot.save ();
            snapshot.translate (offset);
            snapshot.scale (scale, scale);
            base.snapshot (snapshot);
            snapshot.restore ();
        }
    }

    private class WaveIconState : Object {
        private Gtk.Widget widget;
        public double center;
        public double width;
        public double scale;
        public double layout_offset;
        public Graphene.Rect bounds;
        public double visual_offset = 0.0;
        private DockPosition position;

        public WaveIconState (Gtk.Widget widget, Graphene.Rect bounds, double scale,
                              DockPosition position) {
            this.widget = widget;
            this.bounds = bounds;
            this.position = position;
            this.center = position.is_vertical ()
                ? bounds.origin.y + bounds.size.height / 2.0
                : bounds.origin.x + bounds.size.width / 2.0;
            this.width = position.is_vertical () ? bounds.size.height : bounds.size.width;
            this.scale = scale;
            this.layout_offset = 0.0;
        }

        public void set_visual_state (double scale, double offset) {
            if (widget is DockIcon) ((DockIcon) widget).set_visual_state (scale, offset);
            else if (widget is FolderDockIcon) ((FolderDockIcon) widget).set_visual_state (scale, offset);
            else if (widget is TrashDockIcon) ((TrashDockIcon) widget).set_visual_state (scale, offset);
            else ((GridWaveIcon) widget).set_visual_state (scale, offset);
        }

        public bool contains_visual (double x, double y) {
            double visual_x;
            double visual_y;
            if (!position.is_vertical ()) {
                visual_x = bounds.origin.x + visual_offset + bounds.size.width * (1.0 - scale) / 2.0;
                visual_y = bounds.origin.y + (position == DockPosition.TOP ? 0.0
                    : bounds.size.height * (1.0 - scale));
            } else {
                visual_x = bounds.origin.x + (position == DockPosition.LEFT ? 0.0
                    : bounds.size.width * (1.0 - scale));
                visual_y = bounds.origin.y + visual_offset + bounds.size.height * (1.0 - scale) / 2.0;
            }
            return x >= visual_x && x <= visual_x + bounds.size.width * scale &&
                y >= visual_y && y <= visual_y + bounds.size.height * scale;
        }

        public void set_magnified_hover (bool hovered) {
            if (widget is DockIcon) ((DockIcon) widget).set_magnified_hover (hovered);
            else if (widget is FolderDockIcon) ((FolderDockIcon) widget).set_magnified_hover (hovered);
            else if (widget is TrashDockIcon) ((TrashDockIcon) widget).set_magnified_hover (hovered);
            else ((GridWaveIcon) widget).set_magnified_hover (hovered);
        }

        public bool activate_if_visual_only (double x, double y) {
            if (x >= bounds.origin.x && x <= bounds.origin.x + bounds.size.width &&
                y >= bounds.origin.y && y <= bounds.origin.y + bounds.size.height) {
                return false;
            }
            if (!contains_visual (x, y)) return false;

            if (widget is DockIcon) ((DockIcon) widget).activate_button ();
            else if (widget is FolderDockIcon) ((FolderDockIcon) widget).activate_button ();
            else if (widget is TrashDockIcon) ((TrashDockIcon) widget).activate_button ();
            else ((GridWaveIcon) widget).activate_button ();
            return true;
        }

        public bool prepare_drag_if_visual_only (double x, double y, out string? source_id) {
            source_id = null;
            if (x >= bounds.origin.x && x <= bounds.origin.x + bounds.size.width &&
                y >= bounds.origin.y && y <= bounds.origin.y + bounds.size.height) {
                return false;
            }
            if (!contains_visual (x, y)) return false;

            if (widget is DockIcon) {
                source_id = ((DockIcon) widget).desktop_id;
                return true;
            }
            if (widget is FolderDockIcon) {
                source_id = "folder:" + ((FolderDockIcon) widget).folder_path;
                return true;
            }
            return false;
        }

        public Gtk.Widget get_widget () {
            return widget;
        }

        public Gdk.Paintable? create_drag_paintable (out int hotspot_x, out int hotspot_y) {
            hotspot_x = 0;
            hotspot_y = 0;
            if (widget is DockIcon) {
                return ((DockIcon) widget).create_drag_paintable (out hotspot_x, out hotspot_y);
            }
            if (widget is FolderDockIcon) {
                return ((FolderDockIcon) widget).create_drag_paintable (out hotspot_x, out hotspot_y);
            }
            return null;
        }

    }
}
