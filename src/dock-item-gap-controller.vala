namespace XimperShellDock {

    public delegate bool DockItemPredicate (Gtk.Widget widget);

    // Owns the visual gap shown while an item is dragged within one dock
    // section. Both pinned applications and dock folders use this controller,
    // keeping their drag feedback and cancellation behaviour identical.
    public class DockItemGapController : Object {
        private weak Gtk.Box container;
        private DockItemPredicate is_item;
        private int spacer_width;
        private Gtk.Orientation orientation;
        private weak Gtk.Widget? source_item = null;
        private int gap_index = -1;
        private Gtk.Widget? gap = null;
        private Gtk.Widget? old_gap = null;
        private Adw.TimedAnimation? grow_animation = null;
        private Adw.TimedAnimation? shrink_animation = null;

        public bool is_dragging { get { return source_item != null; } }

        public DockItemGapController (Gtk.Box container, int spacer_width,
                                      owned DockItemPredicate is_item,
                                      Gtk.Orientation orientation = Gtk.Orientation.HORIZONTAL) {
            this.container = container;
            this.spacer_width = spacer_width;
            this.is_item = (owned) is_item;
            this.orientation = orientation;
        }

        public void begin (Gtk.Widget item) {
            if (item.get_parent () != container) return;
            source_item = item;
            int index = get_source_index ();
            item.visible = false;
            gap = create_spacer (spacer_width);
            insert_spacer (gap, index);
            gap_index = index;
        }

        public void move_to (int index) {
            if (index == gap_index) return;
            cancel_animations ();
            if (old_gap != null) {
                deferred_remove (old_gap);
                old_gap = null;
            }

            if (gap != null) {
                old_gap = gap;
                var shrinking_gap = old_gap;
                int current_width = orientation == Gtk.Orientation.HORIZONTAL
                    ? shrinking_gap.get_width () : shrinking_gap.get_height ();
                if (current_width <= 0) current_width = spacer_width;
                var target = new Adw.CallbackAnimationTarget ((value) => {
                    shrinking_gap.set_size_request (
                        orientation == Gtk.Orientation.HORIZONTAL ? (int) value : 1,
                        orientation == Gtk.Orientation.VERTICAL ? (int) value : 1);
                });
                shrink_animation = new Adw.TimedAnimation (
                    shrinking_gap, (double) current_width, 0, 150, target
                );
                shrink_animation.easing = Adw.Easing.EASE_OUT_CUBIC;
                shrink_animation.done.connect (() => {
                    if (old_gap == shrinking_gap) old_gap = null;
                    deferred_remove (shrinking_gap);
                });
                shrink_animation.play ();
            }

            gap_index = index;
            gap = create_spacer (0);
            insert_spacer (gap, index);
            var growing_gap = gap;
            var grow_target = new Adw.CallbackAnimationTarget ((value) => {
                growing_gap.set_size_request (
                    orientation == Gtk.Orientation.HORIZONTAL ? (int) value : 1,
                    orientation == Gtk.Orientation.VERTICAL ? (int) value : 1);
            });
            grow_animation = new Adw.TimedAnimation (
                growing_gap, 0, (double) spacer_width, 150, grow_target
            );
            grow_animation.easing = Adw.Easing.EASE_OUT_CUBIC;
            grow_animation.play ();
        }

        public void restore_source_gap () {
            if (source_item == null) {
                clear ();
                return;
            }
            move_to (get_source_index ());
        }

        public int compute_insert_index (double cursor_position) {
            int index = 0;
            var child = container.get_first_child ();
            while (child != null) {
                if (child.visible && is_item (child)) {
                    Graphene.Rect bounds;
                    if (child.compute_bounds (container, out bounds)) {
                        double midpoint = orientation == Gtk.Orientation.HORIZONTAL
                            ? bounds.origin.x + bounds.size.width / 2.0
                            : bounds.origin.y + bounds.size.height / 2.0;
                        if (cursor_position < midpoint) return index;
                    }
                    index++;
                }
                child = child.get_next_sibling ();
            }
            return index;
        }

        public void finish () {
            clear ();
            if (source_item != null) source_item.visible = true;
            source_item = null;
        }

        public void clear () {
            cancel_animations ();
            if (gap != null) {
                deferred_remove (gap);
                gap = null;
            }
            if (old_gap != null) {
                deferred_remove (old_gap);
                old_gap = null;
            }
            gap_index = -1;
        }

        private int get_source_index () {
            if (source_item == null) return 0;
            int index = 0;
            var child = container.get_first_child ();
            while (child != null) {
                if (child == source_item) return index;
                if (child.visible && is_item (child)) index++;
                child = child.get_next_sibling ();
            }
            return index;
        }

        public void set_orientation (Gtk.Orientation value) {
            if (orientation == value) return;
            clear ();
            orientation = value;
        }

        private Gtk.Widget create_spacer (int width) {
            var spacer = new Gtk.Box (orientation, 0);
            spacer.set_size_request (orientation == Gtk.Orientation.HORIZONTAL ? width : 1,
                                     orientation == Gtk.Orientation.VERTICAL ? width : 1);
            spacer.sensitive = false;
            spacer.can_target = false;
            return spacer;
        }

        private void insert_spacer (Gtk.Widget spacer, int before_index) {
            int index = 0;
            var child = container.get_first_child ();
            while (child != null) {
                if (child.visible && is_item (child)) {
                    if (index == before_index) {
                        container.insert_child_after (spacer, child.get_prev_sibling ());
                        return;
                    }
                    index++;
                }
                child = child.get_next_sibling ();
            }
            container.append (spacer);
        }

        private void cancel_animations () {
            if (grow_animation != null) { grow_animation.pause (); grow_animation = null; }
            if (shrink_animation != null) { shrink_animation.pause (); shrink_animation = null; }
        }

        private void deferred_remove (Gtk.Widget widget) {
            widget.visible = false;
            Idle.add (() => {
                var parent = widget.get_parent ();
                if (parent is Gtk.Box) ((Gtk.Box) parent).remove (widget);
                return Source.REMOVE;
            });
        }
    }
}
