namespace XimperShellDock {

    public class DockIcon : Gtk.Box {

        public AppEntry app_entry { get; private set; }
        public string desktop_id { get; private set; }

        private Gtk.Image image;
        private Gtk.Box indicator_box;
        private Gtk.Button button;
        private int icon_size;
        private bool _is_running = false;
        private bool _is_focused = false;
        private uint window_count = 0;
        private double magnification = 1.0;
        private double horizontal_offset = 0.0;
        private double vertical_bounce_offset = 0.0;
        private DockPosition dock_position = DockPosition.BOTTOM;
        private Adw.TimedAnimation? bounce_animation;
        private int bounce_step = 0;
        private bool bouncing_for_launch = false;
        private bool launch_window_detected = false;

        private static Gtk.Popover? active_popover = null;

        public bool is_pinned { get; private set; }
        public bool bounce_on_launch { get; set; default = false; }
        public int bounce_duration { get; set; default = 200; }

        public signal void unpin_requested (string desktop_id);
        public signal void pin_requested (string desktop_id);
        public signal void focus_requested (string desktop_id);
        public signal void windows_requested (DockIcon icon);
        public signal void close_requested (string desktop_id);
        public signal void popover_state_changed (bool open);
        public signal void drag_state_changed (bool active);

        public DockIcon (AppEntry entry, int icon_size, bool pinned = true,
                         bool bounce_on_launch = false, int bounce_duration = 200,
                         DockPosition position = DockPosition.BOTTOM) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app_entry = entry;
            this.desktop_id = entry.desktop_id;
            this.is_pinned = pinned;
            this.icon_size = icon_size;
            this.bounce_on_launch = bounce_on_launch;
            this.bounce_duration = bounce_duration;
            this.dock_position = position;

            halign = Gtk.Align.CENTER;

            button = new Gtk.Button ();
            button.focusable = false;
            button.add_css_class ("dock-icon");
            button.add_css_class ("flat");

            image = new Gtk.Image ();
            if (entry.icon != null) {
                image.gicon = entry.icon;
            } else {
                image.icon_name = "application-x-executable";
            }
            image.pixel_size = icon_size;
            button.set_child (image);
            button.tooltip_text = entry.name;

            button.clicked.connect (() => {
                if (_is_running) {
                    if (window_count > 1) windows_requested (this);
                    else focus_requested (desktop_id);
                } else {
                    if (bounce_on_launch) play_launch_bounce ();
                    entry.launch ();
                }
            });

            append (button);

            // Running indicator dot
            indicator_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            indicator_box.halign = Gtk.Align.CENTER;
            indicator_box.add_css_class ("dock-indicator-box");

            var dot = new Gtk.DrawingArea ();
            dot.set_size_request (6, 3);
            dot.add_css_class ("dock-indicator");
            indicator_box.append (dot);
            indicator_box.visible = false;

            append (indicator_box);

            setup_context_menu ();
            setup_dnd ();
            apply_position (position);
        }

        public void apply_position (DockPosition position) {
            dock_position = position;
            orientation = position.is_vertical () ? Gtk.Orientation.HORIZONTAL
                                                   : Gtk.Orientation.VERTICAL;
            indicator_box.orientation = position.is_vertical () ? Gtk.Orientation.VERTICAL
                                                                  : Gtk.Orientation.HORIZONTAL;
            if (position == DockPosition.LEFT)
                reorder_child_after (indicator_box, null);
            else
                reorder_child_after (indicator_box, button);
            queue_draw ();
        }

        public void set_running (bool running) {
            if (_is_running == running) return;
            _is_running = running;
            if (running) finish_launch_bounce ();
            indicator_box.visible = running;
        }

        public void set_window_count (uint count) {
            window_count = count;
        }

        public void set_focused (bool focused) {
            if (_is_focused == focused) return;
            _is_focused = focused;
            if (focused) {
                button.add_css_class ("dock-icon-focused");
            } else {
                button.remove_css_class ("dock-icon-focused");
            }
        }

        public void update_icon_size (int size) {
            icon_size = size;
            image.pixel_size = size;
        }

        public void activate_button () {
            button.activate ();
        }

        public Gdk.Paintable? create_drag_paintable (out int hotspot_x, out int hotspot_y) {
            int width = get_width ();
            int height = get_height ();
            double scale = magnification;
            double visual_x;
            double visual_y;
            if (!dock_position.is_vertical ()) {
                visual_x = horizontal_offset + width * (1.0 - scale) / 2.0;
                visual_y = (dock_position == DockPosition.TOP ? 0.0 : height * (1.0 - scale)) + vertical_bounce_offset;
            } else {
                visual_x = dock_position == DockPosition.LEFT ? vertical_bounce_offset
                    : width * (1.0 - scale) + vertical_bounce_offset;
                visual_y = horizontal_offset + height * (1.0 - scale) / 2.0;
            }
            int left = (int) (double.max (-visual_x, 0.0) + 0.999);
            int right = (int) (double.max (visual_x + width * scale - width, 0.0) + 0.999);
            int top = (int) (double.max (-visual_y, 0.0) + 0.999);
            int bottom = (int) (double.max (visual_y + height * scale - height, 0.0) + 0.999);

            var snapshot = new Gtk.Snapshot ();
            var offset = Graphene.Point ();
            offset.init (left, top);
            snapshot.translate (offset);
            this.snapshot (snapshot);
            var size = Graphene.Size ();
            size.init (width + left + right, height + top + bottom);
            hotspot_x = left + width / 2;
            hotspot_y = top + height / 2;
            return snapshot.free_to_paintable (size);
        }

        public void set_magnified_hover (bool hovered) {
            if (hovered) button.add_css_class ("dock-icon-magnified-hover");
            else button.remove_css_class ("dock-icon-magnified-hover");
        }

        public void set_visual_state (double scale, double offset) {
            if (magnification == scale && horizontal_offset == offset) return;
            magnification = scale;
            horizontal_offset = offset;
            queue_draw ();
        }

        public void update_bounce_settings (bool enabled, int duration) {
            bounce_on_launch = enabled;
            bounce_duration = duration;
            if (!enabled) stop_launch_bounce ();
        }

        private void play_launch_bounce () {
            if (bounce_animation != null) {
                bounce_animation.pause ();
                bounce_animation = null;
            }
            bouncing_for_launch = true;
            launch_window_detected = false;
            bounce_step = 0;
            play_next_bounce_step ();
        }

        private void play_next_bounce_step () {
            bool moving_up = bounce_step % 2 == 0;
            double bounce_height = icon_size * 0.55;
            if (bounce_height < 14.0) bounce_height = 14.0;
            double outward = dock_position == DockPosition.LEFT || dock_position == DockPosition.TOP ? 1.0 : -1.0;
            double target_offset = moving_up ? outward * bounce_height : 0.0;
            uint duration;
            if (launch_window_detected) {
                duration = moving_up ? (uint) (bounce_duration * 7 / 10)
                                     : (uint) (bounce_duration * 9 / 10);
            } else {
                duration = moving_up ? (uint) bounce_duration : (uint) (bounce_duration * 13 / 10);
            }
            var target = new Adw.CallbackAnimationTarget ((value) => {
                vertical_bounce_offset = value;
                queue_draw ();
            });
            bounce_animation = new Adw.TimedAnimation (
                this, vertical_bounce_offset, target_offset, duration, target
            );
            bounce_animation.easing = moving_up
                ? Adw.Easing.EASE_OUT_CUBIC
                : Adw.Easing.EASE_IN_CUBIC;
            bounce_animation.done.connect (() => {
                bounce_step++;
                bool just_finished_down = bounce_step % 2 == 0;
                if (bouncing_for_launch && !(launch_window_detected && just_finished_down)) {
                    Idle.add (() => {
                        play_next_bounce_step ();
                        return Source.REMOVE;
                    });
                } else {
                    stop_launch_bounce ();
                }
            });
            bounce_animation.play ();
        }

        private void stop_launch_bounce () {
            bouncing_for_launch = false;
            if (bounce_animation != null) {
                bounce_animation.pause ();
                bounce_animation = null;
            }
            vertical_bounce_offset = 0.0;
            queue_draw ();
        }

        private void finish_launch_bounce () {
            if (!bouncing_for_launch) return;
            launch_window_detected = true;
        }

        protected override void snapshot (Gtk.Snapshot snapshot) {
            // Launch bounce is independent of hover magnification.  Keep
            // drawing through the transform path while it has a vertical
            // offset, even when the icon has its normal scale.
            if (magnification == 1.0 && horizontal_offset == 0.0 &&
                vertical_bounce_offset == 0.0) {
                base.snapshot (snapshot);
                return;
            }

            float scale = (float) magnification;
            var offset = Graphene.Point ();
            if (!dock_position.is_vertical ()) {
                offset.init (
                    (float) horizontal_offset + (get_width () * (1.0f - scale)) / 2.0f,
                    (dock_position == DockPosition.TOP ? 0.0f : get_height () * (1.0f - scale)) + (float) vertical_bounce_offset
                );
            } else {
                offset.init (
                    dock_position == DockPosition.LEFT ? (float) vertical_bounce_offset
                        : get_width () * (1.0f - scale) + (float) vertical_bounce_offset,
                    (float) horizontal_offset + (get_height () * (1.0f - scale)) / 2.0f
                );
            }

            snapshot.save ();
            snapshot.translate (offset);
            snapshot.scale (scale, scale);
            base.snapshot (snapshot);
            snapshot.restore ();
        }

        private void setup_dnd () {
            var source = new Gtk.DragSource ();
            source.set_actions (Gdk.DragAction.MOVE);
            Gdk.Paintable? drag_paintable = null;
            int drag_w = 0;
            int drag_h = 0;
            source.prepare.connect ((x, y) => {
                // Snapshot the icon before it gets hidden
                drag_paintable = create_drag_paintable (out drag_w, out drag_h);
                return new Gdk.ContentProvider.for_value (desktop_id);
            });
            source.drag_begin.connect ((drag) => {
                if (drag_paintable != null) {
                    source.set_icon (drag_paintable, drag_w / 2, drag_h / 2);
                }
                drag_state_changed (true);
            });
            source.drag_end.connect ((drag, del) => {
                drag_state_changed (false);
            });
            button.add_controller (source);
        }

        private void setup_context_menu () {
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_SECONDARY;
            gesture.pressed.connect ((n, x, y) => {
                open_context_popover ();
            });
            button.add_controller (gesture);
        }

        private Gtk.Button make_menu_item (string label) {
            var btn = new Gtk.Button ();
            btn.add_css_class ("flat");
            btn.label = label;
            return btn;
        }

        private void open_context_popover () {
            // Close any other icon's popover
            if (active_popover != null) {
                active_popover.popdown ();
            }

            var popover = new Gtk.Popover ();
            popover.set_parent (button);
            popover.has_arrow = true;
            popover.position = dock_position.inward_popover_position ();
            popover.add_css_class ("menu");

            var menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            // Desktop actions from .desktop file
            var desktop_actions = app_entry.list_actions ();
            if (desktop_actions.length > 0) {
                foreach (var action_id in desktop_actions) {
                    var action_name = app_entry.get_action_name (action_id);
                    var btn = make_menu_item (action_name);
                    var aid = action_id;
                    btn.clicked.connect (() => {
                        popover.popdown ();
                        app_entry.launch_action (aid);
                    });
                    menu_box.append (btn);
                }
                menu_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            }

            // Pin/Unpin
            if (is_pinned) {
                var btn = make_menu_item (_("Unpin"));
                btn.clicked.connect (() => {
                    popover.popdown ();
                    unpin_requested (desktop_id);
                });
                menu_box.append (btn);
            } else {
                var btn = make_menu_item (_("Pin to Dock"));
                btn.clicked.connect (() => {
                    popover.popdown ();
                    pin_requested (desktop_id);
                });
                menu_box.append (btn);
            }

            // Quit — only if running
            if (_is_running) {
                menu_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                var btn = make_menu_item (_("Quit"));
                btn.clicked.connect (() => {
                    popover.popdown ();
                    close_requested (desktop_id);
                });
                menu_box.append (btn);
            }

            popover.set_child (menu_box);

            popover.closed.connect (() => {
                popover_state_changed (false);
                if (active_popover == popover) active_popover = null;
                popover.unparent ();
            });

            popover_state_changed (true);
            active_popover = popover;
            popover.popup ();
        }
    }
}
