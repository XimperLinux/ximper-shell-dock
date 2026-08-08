namespace XimperShellDock {

    private class GridWaveIcon : Gtk.Box {
        private double magnification = 1.0;
        private double horizontal_offset = 0.0;

        public GridWaveIcon () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            halign = Gtk.Align.CENTER;
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
    }

    private class WaveIconState : Object {
        private Gtk.Widget widget;
        public double center;
        public double width;
        public double scale;
        public double layout_offset;

        public WaveIconState (Gtk.Widget widget, double center, double width, double scale) {
            this.widget = widget;
            this.center = center;
            this.width = width;
            this.scale = scale;
            this.layout_offset = 0.0;
        }

        public void set_visual_state (double scale, double offset) {
            if (widget is DockIcon) ((DockIcon) widget).set_visual_state (scale, offset);
            else ((GridWaveIcon) widget).set_visual_state (scale, offset);
        }

    }

    public class DockWindow : Gtk.Window {

        public signal void grid_requested ();

        private weak Application app;
        private Gdk.Monitor? monitor;
        private int niri_logical_monitor_width = 0;
        private Gtk.Box wave_surface;
        private Gtk.Box dock_content;
        private Gtk.Box main_box;
        private Gtk.Box icon_box;
        private Gtk.Box running_box;
        private GridWaveIcon grid_wrapper;
        private Gtk.Button grid_button;
        private Gtk.Image grid_image;
        private bool autohide_enabled = false;
        private bool popover_open = false;
        private bool dnd_active = false;
        private bool cursor_inside = false;
        private uint hide_timeout_id = 0;
        private uint watchdog_id = 0;
        private uint magnification_tick_id = 0;
        private int64 magnification_last_frame_time = 0;
        private double wave_focus_x = 0.0;
        private double wave_target_x = 0.0;
        private double wave_strength = 0.0;
        private double wave_target_strength = 0.0;
        private weak DockTrigger? linked_trigger = null;
        private int64 show_timestamp = 0;
        private int64 leave_timestamp = 0;

        // DnD spacer-based gap animation
        private weak DockIcon? drag_source_icon = null;
        private int drop_gap_index = -1;
        private Gtk.Widget? gap_spacer = null;
        private Gtk.Widget? gap_spacer_old = null;
        private Adw.TimedAnimation? gap_grow_anim = null;
        private Adw.TimedAnimation? gap_shrink_anim = null;

        private int DOCK_HEIGHT = 64;
        private int effective_icon_size = 48;
        private const int HIDE_DELAY_MS = 300;
        private const int SHOW_GRACE_MS = 600;
        // Below this, the button's target becomes too small to use reliably.
        private const int MIN_ICON_SIZE = 16;
        private const int FLOATING_SIDE_MARGIN = 16;
        private const double WAVE_ICON_GAP = 6.0;

        public DockWindow (Application app, Gdk.Monitor? monitor = null) {
            this.app = app;
            this.monitor = monitor;
            refresh_niri_logical_monitor_width ();
            this.title = "Ximper Shell Dock";
            this.decorated = false;

            add_css_class ("dock-window");
            DOCK_HEIGHT = app.config.icon_size + 12;
            effective_icon_size = app.config.icon_size;

            LayerShellHelper.setup_dock_floating (this, 8, LayerShellHelper.parse_layer (app.config.layer));
            if (monitor != null) {
                GtkLayerShell.set_monitor (this, monitor);
                monitor.notify["geometry"].connect (() => {
                    refresh_niri_logical_monitor_width ();
                    update_icon_sizes_to_fit ();
                });
            }
            apply_mode ();

            build_ui ();
            populate_icons ();

            app.config.notify["icon-size"].connect (() => {
                rebuild_dock ();
            });
            app.config.notify["magnify-on-hover"].connect (() => {
                if (!app.config.magnify_on_hover) reset_icon_magnification ();
                update_icon_sizes_to_fit ();
            });
            app.config.notify["magnify-scale"].connect (() => {
                update_icon_sizes_to_fit ();
            });
            app.config.notify["bounce-on-launch"].connect (() => {
                update_box_bounce_setting (icon_box);
                update_box_bounce_setting (running_box);
                update_icon_sizes_to_fit ();
            });
            app.config.notify["bounce-duration"].connect (() => {
                update_box_bounce_setting (icon_box);
                update_box_bounce_setting (running_box);
            });

            var motion = new Gtk.EventControllerMotion ();
            motion.leave.connect (() => {
                cursor_inside = false;
                reset_icon_magnification ();
                leave_timestamp = GLib.get_monotonic_time () / 1000;
                if (autohide_enabled && !popover_open && !dnd_active) {
                    schedule_hide ();
                }
            });
            motion.enter.connect ((x, y) => {
                cursor_inside = true;
                show_timestamp = GLib.get_monotonic_time () / 1000;
                cancel_hide ();
            });
            motion.motion.connect ((x, y) => {
                update_icon_magnification (x);
            });
            ((Gtk.Widget) this).add_controller (motion);
        }

        public void set_trigger (DockTrigger trigger) {
            this.linked_trigger = trigger;
        }

        public void apply_mode () {
            GtkLayerShell.set_layer (this, LayerShellHelper.parse_layer (app.config.layer));
            LayerShellHelper.apply_dock_mode (this, app.config.dock_mode, DOCK_HEIGHT);
            if (get_child () != null) {
                dock_content.hexpand = app.config.dock_mode == DockMode.PINNED;
            }
        }

        public void enable_autohide (bool enabled) {
            autohide_enabled = enabled;
            if (!enabled) {
                cancel_hide ();
                if (watchdog_id != 0) { Source.remove (watchdog_id); watchdog_id = 0; }
                set_visible (true);
            } else {
                if (watchdog_id == 0) {
                    watchdog_id = Timeout.add (400, () => {
                        bool on_trigger = linked_trigger != null && linked_trigger.cursor_on_trigger;
                        int64 now = GLib.get_monotonic_time () / 1000;
                        bool in_show_grace = (now - show_timestamp) < SHOW_GRACE_MS;
                        bool in_leave_grace = (now - leave_timestamp) < HIDE_DELAY_MS;
                        if (visible && !cursor_inside && !on_trigger && !popover_open && !dnd_active && autohide_enabled && !in_show_grace && !in_leave_grace) {
                            hide_animated ();
                        }
                        return Source.CONTINUE;
                    });
                }
            }
        }

        public void show_animated () {
            cancel_hide ();
            show_timestamp = GLib.get_monotonic_time () / 1000;
            set_visible (true);
            opacity = 0;

            var target = new Adw.PropertyAnimationTarget (this, "opacity");
            var anim = new Adw.TimedAnimation (this, 0.0, 1.0, 200, target);
            anim.play ();
        }

        public void hide_animated () {
            cursor_inside = false;
            var target = new Adw.PropertyAnimationTarget (this, "opacity");
            var anim = new Adw.TimedAnimation (this, 1.0, 0.0, 200, target);
            anim.done.connect (() => {
                set_visible (false);
                opacity = 1;
            });
            anim.play ();
        }

        public void update_indicators () {
            var tracker = app.window_tracker;

            // Update pinned icons
            var child = icon_box.get_first_child ();
            while (child != null) {
                if (child is DockIcon) {
                    var icon = (DockIcon) child;
                    icon.set_running (tracker.is_running (icon.desktop_id));
                    icon.set_focused (tracker.is_focused (icon.desktop_id));
                }
                child = child.get_next_sibling ();
            }

            // Show running-but-not-pinned apps
            var running_child = running_box.get_first_child ();
            while (running_child != null) {
                var next = running_child.get_next_sibling ();
                running_box.remove (running_child);
                running_child = next;
            }

            var pinned = app.config.pinned_apps;
            var shown_classes = new GenericArray<string> ();

            // Collect pinned classes
            if (pinned != null) {
                for (uint i = 0; i < pinned.length; i++) {
                    shown_classes.add (pinned[i]);
                }
            }

            // Add running apps not in pinned
            if (tracker.running_apps == null) return;
            for (uint i = 0; i < tracker.running_apps.length; i++) {
                var running = tracker.running_apps[i];
                bool already_shown = false;

                for (uint j = 0; j < shown_classes.length; j++) {
                    if (tracker.matches_desktop_id (running.app_class, shown_classes[j])) {
                        already_shown = true;
                        break;
                    }
                }

                if (!already_shown) {
                    // Check if we already added this class
                    bool dup = false;
                    for (uint k = 0; k < shown_classes.length; k++) {
                        if (shown_classes[k] == running.app_class) {
                            dup = true;
                            break;
                        }
                    }
                    if (dup) continue;

                    shown_classes.add (running.app_class);

                    // Find the AppEntry for this running app
                    var entry = find_entry_by_class (running.app_class);
                    if (entry != null) {
                        var icon = new DockIcon (entry, app.config.icon_size, false,
                                                 app.config.bounce_on_launch,
                                                 app.config.bounce_duration);
                        icon.set_running (true);
                        icon.set_focused (tracker.focused_class == running.app_class);
                        icon.pin_requested.connect ((id) => {
                            pin_app (id);
                        });
                        icon.focus_requested.connect ((id) => {
                            app.window_tracker.focus_window (id);
                        });
                        icon.close_requested.connect ((id) => {
                            app.window_tracker.close_app (id);
                        });
                        icon.popover_state_changed.connect ((open) => {
                            popover_open = open;
                            if (open) cancel_hide ();
                            else if (autohide_enabled) schedule_hide ();
                        });
                        running_box.append (icon);
                    }
                }
            }

            // Show/hide separator
            bool has_running = running_box.get_first_child () != null;
            running_box.visible = has_running;
            update_icon_sizes_to_fit ();
            queue_resize ();
        }

        private AppEntry? find_entry_by_class (string app_class) {
            var apps = app.app_provider.apps;
            if (apps == null) return null;
            for (uint i = 0; i < apps.length; i++) {
                var id = apps[i].desktop_id.replace (".desktop", "");
                if (id == app_class || id.down () == app_class.down ()) {
                    return apps[i];
                }
                var parts = id.split (".");
                if (parts.length > 0 &&
                    parts[parts.length - 1].down () == app_class.down ()) {
                    return apps[i];
                }
            }
            return null;
        }

        private void build_ui () {
            var main_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            this.main_box = main_box;
            main_box.halign = Gtk.Align.CENTER;
            main_box.valign = Gtk.Align.CENTER;

            // Grid button — same structure as DockIcon
            grid_wrapper = new GridWaveIcon ();

            grid_button = new Gtk.Button ();
            grid_button.add_css_class ("dock-icon");
            grid_button.add_css_class ("flat");
            grid_image = new Gtk.Image.from_icon_name ("view-app-grid-symbolic");
            grid_image.pixel_size = app.config.icon_size;
            grid_button.set_child (grid_image);
            grid_button.tooltip_text = "Applications";
            grid_button.clicked.connect (() => {
                grid_requested ();
            });
            grid_wrapper.append (grid_button);

            // Match DockIcon indicator_box height
            var grid_indicator = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            grid_indicator.add_css_class ("dock-indicator-box");
            grid_wrapper.append (grid_indicator);

            // Pinned icons
            icon_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            icon_box.overflow = Gtk.Overflow.VISIBLE;

            // Running (not pinned) icons
            running_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            running_box.overflow = Gtk.Overflow.VISIBLE;
            running_box.visible = false;

            main_box.append (grid_wrapper);
            main_box.append (icon_box);
            main_box.append (running_box);

            dock_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            dock_content.add_css_class ("dock-content");
            dock_content.halign = Gtk.Align.CENTER;
            dock_content.valign = Gtk.Align.END;
            dock_content.hexpand = app.config.dock_mode == DockMode.PINNED;
            dock_content.append (main_box);

            wave_surface = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            wave_surface.halign = Gtk.Align.CENTER;
            wave_surface.valign = Gtk.Align.END;
            wave_surface.append (dock_content);

            // DropTarget on icon_box — reorder with animated spacer gap
            var icon_drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            icon_drop.motion.connect ((x, y) => {
                int idx = compute_insert_index (x);
                move_gap_to (idx);
                return Gdk.DragAction.MOVE;
            });
            icon_drop.leave.connect (() => {
                // Return spacer to source position if dragging from dock
                if (drag_source_icon != null) {
                    int src_idx = get_source_visual_index ();
                    move_gap_to (src_idx);
                } else {
                    remove_all_spacers ();
                }
            });
            icon_drop.drop.connect ((val, x, y) => {
                var source_id = (string) val;
                if (source_id == null || source_id.has_prefix ("folder:")) return false;
                int idx = compute_insert_index (x);
                remove_all_spacers ();
                reorder_pinned_at (source_id, idx);
                return true;
            });
            icon_box.add_controller (icon_drop);

            // DropTarget on dock — accept apps dragged from grid or other sources
            var dock_drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            dock_drop.drop.connect ((val, x, y) => {
                var source_id = (string) val;
                if (source_id == null || source_id.has_prefix ("folder:")) return false;
                pin_app (source_id);
                return true;
            });
            main_box.add_controller (dock_drop);

            set_child (wave_surface);

            setup_dock_context_menu (main_box);
        }

        private void setup_dock_context_menu (Gtk.Widget target) {
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_SECONDARY;
            gesture.pressed.connect ((n, x, y) => {
                show_dock_menu (target, x, y);
            });
            target.add_controller (gesture);
        }

        private void show_dock_menu (Gtk.Widget target, double x, double y) {
            var popover = new Gtk.Popover ();
            popover.set_parent (target);
            popover.has_arrow = true;
            popover.autohide = true;
            Gdk.Rectangle pointing_rect = Gdk.Rectangle ();
            pointing_rect.x = (int) x;
            pointing_rect.y = (int) y;
            pointing_rect.width = 1;
            pointing_rect.height = 1;
            popover.set_pointing_to (pointing_rect);

            var menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            menu_box.margin_top = 4;
            menu_box.margin_bottom = 4;
            menu_box.margin_start = 4;
            menu_box.margin_end = 4;

            var settings_btn = new Gtk.Button.with_label ("Settings");
            settings_btn.add_css_class ("flat");
            settings_btn.halign = Gtk.Align.FILL;
            settings_btn.clicked.connect (() => {
                popover.popdown ();
                open_settings ();
            });
            menu_box.append (settings_btn);

            popover.set_child (menu_box);
            popover_open = true;
            cancel_hide ();
            popover.popup ();

            popover.closed.connect (() => {
                popover_open = false;
                popover.unparent ();
                if (autohide_enabled) {
                    schedule_hide ();
                }
            });
        }

        private void open_settings () {
            var settings = new SettingsWindow (app);
            settings.present ();
        }

        public void rebuild_dock () {
            DOCK_HEIGHT = app.config.icon_size + 12;
            populate_icons ();
            update_indicators ();
            apply_mode ();
            queue_resize ();
        }

        // The configured size is an upper bound.  Floating layer-shell
        // surfaces are sized from their natural width, so GTK cannot shrink
        // this box for us when it grows wider than its monitor.
        private void update_icon_sizes_to_fit () {
            int available_width = get_available_width ();
            if (available_width <= 0) return;

            int initial_reserve = get_wave_horizontal_reserve ();
            wave_surface.margin_start = initial_reserve;
            wave_surface.margin_end = initial_reserve;

            int size = app.config.icon_size;
            int minimum = 0;
            int natural = 0;

            // Measure after every candidate size instead of duplicating CSS
            // paddings and Gtk.Box spacing in a width formula.
            while (size > MIN_ICON_SIZE) {
                set_effective_icon_size (size);
                dock_content.measure (Gtk.Orientation.HORIZONTAL, -1,
                                  out minimum, out natural, null, null);
                if (natural <= available_width) break;
                size--;
            }

            set_effective_icon_size (size);
            dock_content.measure (Gtk.Orientation.HORIZONTAL, -1,
                              out minimum, out natural, null, null);
            if (natural > available_width) {
                warning ("Dock contents exceed monitor width even at minimum icon size (%dpx)",
                         MIN_ICON_SIZE);
            }
            int height = get_dock_height ();
            if (DOCK_HEIGHT != height) {
                DOCK_HEIGHT = height;
                set_size_request (-1, DOCK_HEIGHT);
                apply_mode ();
            }
            if (wave_strength < 0.002) {
                main_box.margin_start = 0;
                main_box.margin_end = 0;
            }
            wave_surface.margin_start = get_wave_horizontal_reserve ();
            wave_surface.margin_end = get_wave_horizontal_reserve ();
            queue_resize ();
        }

        private int get_available_width () {
            if (monitor == null) return 0;
            // GDK's Wayland monitor geometry may expose the pre-transform
            // mode width. Niri reports the actual logical output size, which
            // matters for portrait displays.
            int width = niri_logical_monitor_width > 0
                ? niri_logical_monitor_width
                : monitor.geometry.width;
            if (app.config.dock_mode == DockMode.FLOATING) {
                width -= FLOATING_SIDE_MARGIN * 2;
            }
            return width;
        }

        private int get_dock_height () {
            int height = effective_icon_size + 12;

            // The outer surface stays transparent; the visible dock-content
            // remains at its normal height along the bottom edge.
            if (app.config.magnify_on_hover) {
                int icon_height = effective_icon_size + 15;
                height += (icon_height * (app.config.magnify_scale - 100) + 99) / 100;
            }
            if (app.config.bounce_on_launch) {
                height += (effective_icon_size * 55 + 99) / 100;
            }
            return height;
        }

        private int get_wave_horizontal_reserve () {
            if (!app.config.magnify_on_hover || app.config.dock_mode != DockMode.FLOATING) {
                return 0;
            }
            double growth = (app.config.magnify_scale - 100) / 100.0;
            return (int) ((effective_icon_size + 15) * growth *
                app.config.magnify_radius * 0.45 +
                WAVE_ICON_GAP * app.config.magnify_radius * 0.6 + 0.5);
        }

        private void refresh_niri_logical_monitor_width () {
            niri_logical_monitor_width = 0;
            if (monitor == null || !NiriHelper.is_available ()) return;

            try {
                string stdout_buf;
                int exit_status;
                Process.spawn_command_line_sync (
                    "niri msg --json outputs", out stdout_buf, null, out exit_status
                );
                if (exit_status != 0 || stdout_buf == null || stdout_buf.length == 0) return;

                var parser = new Json.Parser ();
                parser.load_from_data (stdout_buf);
                var outputs = parser.get_root ().get_object ();
                var output = outputs.get_object_member (monitor.connector);
                if (output == null || !output.has_member ("logical")) return;

                var logical = output.get_object_member ("logical");
                if (logical != null && logical.has_member ("width")) {
                    niri_logical_monitor_width = (int) logical.get_int_member ("width");
                }
            } catch (Error e) {
                // Fall back to the GDK geometry when Niri is unavailable.
            }
        }

        private void set_effective_icon_size (int size) {
            if (effective_icon_size == size) return;
            effective_icon_size = size;
            grid_image.pixel_size = size;
            update_box_icon_sizes (icon_box, size);
            update_box_icon_sizes (running_box, size);
        }

        private void update_box_icon_sizes (Gtk.Box box, int size) {
            var child = box.get_first_child ();
            while (child != null) {
                if (child is DockIcon) {
                    ((DockIcon) child).update_icon_size (size);
                }
                child = child.get_next_sibling ();
            }
        }

        private void update_box_bounce_setting (Gtk.Box box) {
            var child = box.get_first_child ();
            while (child != null) {
                if (child is DockIcon) {
                    ((DockIcon) child).update_bounce_settings (
                        app.config.bounce_on_launch, app.config.bounce_duration
                    );
                }
                child = child.get_next_sibling ();
            }
        }

        private void update_icon_magnification (double cursor_x) {
            if (!app.config.magnify_on_hover || dnd_active) return;
            if (wave_strength < 0.002 && wave_target_strength == 0.0) {
                wave_focus_x = cursor_x;
            }
            wave_target_x = cursor_x;
            wave_target_strength = 1.0;
            ensure_magnification_animation ();
        }

        private void collect_box_wave_items (Gtk.Box box, GenericArray<WaveIconState> icons) {
            var child = box.get_first_child ();
            while (child != null) {
                if (child is DockIcon) collect_wave_item (child, icons);
                child = child.get_next_sibling ();
            }
        }

        private void collect_wave_item (Gtk.Widget widget, GenericArray<WaveIconState> icons) {
            Graphene.Rect bounds;
            if (!widget.compute_bounds (this, out bounds)) return;
            icons.add (new WaveIconState (
                widget, bounds.origin.x + bounds.size.width / 2.0, bounds.size.width, 1.0
            ));
        }

        private void apply_wave_layout () {
            int radius = (int) (effective_icon_size * app.config.magnify_radius);
            var icons = new GenericArray<WaveIconState> ();
            collect_wave_item (grid_wrapper, icons);
            collect_box_wave_items (icon_box, icons);
            collect_box_wave_items (running_box, icons);

            for (uint i = 0; i < icons.length; i++) {
                double distance = (icons[i].center - wave_focus_x).abs ();
                double t = (distance / radius).clamp (0.0, 1.0);
                double smoothstep = t * t * (3.0 - 2.0 * t);
                icons[i].scale = 1.0 +
                    ((app.config.magnify_scale - 100) / 100.0) * wave_strength *
                    (1.0 - smoothstep);
            }

            if (icons.length == 0) return;

            // Integrate the extra width from left to right. Unlike anchoring
            // to the nearest icon, this mapping is continuous as the cursor
            // crosses from one icon to the next.
            double accumulated_width = 0.0;
            double maximum_growth = (app.config.magnify_scale - 100) / 100.0;
            for (uint i = 0; i < icons.length; i++) {
                double growth = icons[i].scale - 1.0;
                // Leave real space between scaled snapshots. Without it the
                // geometry merely touches, but anti-aliased corners and
                // shadows still make neighbouring icons appear to overlap.
                double clearance = maximum_growth > 0.0
                    ? WAVE_ICON_GAP * growth / maximum_growth
                    : 0.0;
                double extra_width = icons[i].width * growth + clearance;
                icons[i].layout_offset = accumulated_width + extra_width / 2.0;
                accumulated_width += extra_width;
            }

            double focus_offset = icons[0].layout_offset;
            if (wave_focus_x >= icons[icons.length - 1].center) {
                focus_offset = icons[icons.length - 1].layout_offset;
            } else {
                for (uint i = 1; i < icons.length; i++) {
                    if (wave_focus_x > icons[i].center) continue;
                    double span = icons[i].center - icons[i - 1].center;
                    double progress = span > 0.0
                        ? ((wave_focus_x - icons[i - 1].center) / span).clamp (0.0, 1.0)
                        : 0.0;
                    focus_offset = icons[i - 1].layout_offset +
                        (icons[i].layout_offset - icons[i - 1].layout_offset) * progress;
                    break;
                }
            }

            double base_left = double.MAX;
            double base_right = -double.MAX;
            double visual_left = double.MAX;
            double visual_right = -double.MAX;
            for (uint i = 0; i < icons.length; i++) {
                icons[i].set_visual_state (
                    icons[i].scale, icons[i].layout_offset - focus_offset
                );
                base_left = double.min (base_left, icons[i].center - icons[i].width / 2.0);
                base_right = double.max (base_right, icons[i].center + icons[i].width / 2.0);
                visual_left = double.min (visual_left,
                    icons[i].center - icons[i].width * icons[i].scale / 2.0 +
                    icons[i].layout_offset - focus_offset);
                visual_right = double.max (visual_right,
                    icons[i].center + icons[i].width * icons[i].scale / 2.0 +
                    icons[i].layout_offset - focus_offset);
            }

            int needed_start = (int) (double.max (base_left - visual_left, 0.0) + 1.0);
            int needed_end = (int) (double.max (visual_right - base_right, 0.0) + 1.0);
            if (main_box.margin_start != needed_start || main_box.margin_end != needed_end) {
                main_box.margin_start = needed_start;
                main_box.margin_end = needed_end;
                queue_resize ();
            }
        }

        private void reset_icon_magnification () {
            wave_target_strength = 0.0;
            ensure_magnification_animation ();
        }

        private void ensure_magnification_animation () {
            if (magnification_tick_id != 0) return;
            magnification_last_frame_time = 0;
            magnification_tick_id = add_tick_callback ((widget, frame_clock) => {
                int64 frame_time = frame_clock.get_frame_time ();
                if (magnification_last_frame_time == 0) {
                    magnification_last_frame_time = frame_time;
                    return Source.CONTINUE;
                }

                double elapsed = (frame_time - magnification_last_frame_time) / 1000000.0;
                magnification_last_frame_time = frame_time;
                double normalized_elapsed = elapsed * 1000.0 / app.config.magnify_animation_duration;
                double progress = (normalized_elapsed * 2.0).clamp (0.0, 1.0);
                wave_focus_x += (wave_target_x - wave_focus_x) * progress;
                wave_strength += (wave_target_strength - wave_strength) * progress;
                apply_wave_layout ();
                if ((wave_target_x - wave_focus_x).abs () < 0.25 &&
                    (wave_target_strength - wave_strength).abs () < 0.002) {
                    wave_focus_x = wave_target_x;
                    wave_strength = wave_target_strength;
                    apply_wave_layout ();
                    magnification_tick_id = 0;
                    return Source.REMOVE;
                }
                return Source.CONTINUE;
            });
        }


        private void populate_icons () {
            var child = icon_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                icon_box.remove (child);
                child = next;
            }
            gap_spacer = null;
            gap_spacer_old = null;
            drop_gap_index = -1;
            drag_source_icon = null;

            var pinned = app.config.pinned_apps;
            if (pinned == null) return;
            for (uint i = 0; i < pinned.length; i++) {
                var entry = app.app_provider.find_by_desktop_id (pinned[i]);
                if (entry != null) {
                    var icon = new DockIcon (entry, app.config.icon_size, true,
                                             app.config.bounce_on_launch,
                                             app.config.bounce_duration);
                    icon.unpin_requested.connect ((id) => {
                        unpin_app (id);
                    });
                    icon.focus_requested.connect ((id) => {
                        app.window_tracker.focus_window (id);
                    });
                    icon.close_requested.connect ((id) => {
                        app.window_tracker.close_app (id);
                    });
                    icon.popover_state_changed.connect ((open) => {
                        popover_open = open;
                        if (open) cancel_hide ();
                        else if (autohide_enabled) schedule_hide ();
                    });
                    icon.drag_state_changed.connect ((active) => {
                        dnd_active = active;
                        if (active) {
                            reset_icon_magnification ();
                            begin_icon_drag (icon);
                        } else {
                            end_icon_drag ();
                        }
                    });
                    icon_box.append (icon);
                }
            }
            update_icon_sizes_to_fit ();
        }

        // ── DnD gap management ──────────────────────────────────

        private int get_spacer_width () {
            return effective_icon_size + 8;
        }

        // Called when an icon drag begins. Hides the source and
        // inserts a full-size spacer at its position so that
        // the total box width stays constant — no re-centering.
        private void begin_icon_drag (DockIcon icon) {
            drag_source_icon = icon;
            cancel_hide ();

            // Find visual index of the source before hiding
            int src_idx = 0;
            var child = icon_box.get_first_child ();
            while (child != null) {
                if (child == icon) break;
                if (child.visible && child is DockIcon) src_idx++;
                child = child.get_next_sibling ();
            }

            icon.visible = false;

            // Place spacer at source position (full width, no animation)
            int w = get_spacer_width ();
            gap_spacer = create_spacer (w);
            insert_spacer_at (gap_spacer, src_idx);
            drop_gap_index = src_idx;
        }

        // Called when the drag ends (drop or cancel).
        private void end_icon_drag () {
            remove_all_spacers ();
            if (drag_source_icon != null) {
                drag_source_icon.visible = true;
            }
            drag_source_icon = null;
        }

        // Get the visual index where the source icon was (among
        // visible DockIcons, excluding the hidden source).
        private int get_source_visual_index () {
            if (drag_source_icon == null) return 0;
            int idx = 0;
            var child = icon_box.get_first_child ();
            while (child != null) {
                if (child == drag_source_icon) return idx;
                if (child is DockIcon && child.visible) idx++;
                child = child.get_next_sibling ();
            }
            return idx;
        }

        // Compute insertion index from cursor X. Only considers
        // visible DockIcon widgets — spacers are skipped.
        private int compute_insert_index (double cursor_x) {
            int index = 0;
            var child = icon_box.get_first_child ();
            while (child != null) {
                if (child.visible && child is DockIcon) {
                    Graphene.Rect bounds;
                    if (child.compute_bounds (icon_box, out bounds)) {
                        double mid = bounds.origin.x + bounds.size.width / 2.0;
                        if (cursor_x < mid) return index;
                    }
                    index++;
                }
                child = child.get_next_sibling ();
            }
            return index;
        }

        // Move the gap spacer to a new position. Uses two spacers
        // simultaneously — old one shrinks, new one grows — so
        // total width stays constant and icons slide smoothly.
        private void move_gap_to (int new_index) {
            if (new_index == drop_gap_index) return;

            int w = get_spacer_width ();

            // Cancel running animations
            if (gap_grow_anim != null) { gap_grow_anim.pause (); gap_grow_anim = null; }
            if (gap_shrink_anim != null) { gap_shrink_anim.pause (); gap_shrink_anim = null; }

            // Clean up any leftover old spacer
            if (gap_spacer_old != null) {
                deferred_remove (gap_spacer_old);
                gap_spacer_old = null;
            }

            // Demote current spacer to "old" — will shrink
            if (gap_spacer != null) {
                gap_spacer_old = gap_spacer;
                var old_sp = gap_spacer_old;
                int cur_w = old_sp.get_width ();
                if (cur_w <= 0) cur_w = w;
                var shrink_tgt = new Adw.CallbackAnimationTarget ((val) => {
                    old_sp.set_size_request ((int) val, 1);
                });
                gap_shrink_anim = new Adw.TimedAnimation (old_sp, (double) cur_w, 0, 150, shrink_tgt);
                gap_shrink_anim.easing = Adw.Easing.EASE_OUT_CUBIC;
                gap_shrink_anim.done.connect (() => {
                    if (gap_spacer_old == old_sp) gap_spacer_old = null;
                    deferred_remove (old_sp);
                });
                gap_shrink_anim.play ();
            }

            // Create new spacer at the target position — will grow
            drop_gap_index = new_index;
            gap_spacer = create_spacer (0);
            insert_spacer_at (gap_spacer, new_index);

            var new_sp = gap_spacer;
            var grow_tgt = new Adw.CallbackAnimationTarget ((val) => {
                new_sp.set_size_request ((int) val, 1);
            });
            gap_grow_anim = new Adw.TimedAnimation (new_sp, 0, (double) w, 150, grow_tgt);
            gap_grow_anim.easing = Adw.Easing.EASE_OUT_CUBIC;
            gap_grow_anim.play ();
        }

        // Insert a spacer widget before the Nth visible DockIcon.
        // If index >= visible count, appends at the end.
        private void insert_spacer_at (Gtk.Widget spacer, int before_index) {
            int vis = 0;
            var child = icon_box.get_first_child ();
            while (child != null) {
                if (child.visible && child is DockIcon) {
                    if (vis == before_index) {
                        // insert_child_after(widget, null) prepends
                        var prev = child.get_prev_sibling ();
                        icon_box.insert_child_after (spacer, prev);
                        return;
                    }
                    vis++;
                }
                child = child.get_next_sibling ();
            }
            icon_box.append (spacer);
        }

        private Gtk.Widget create_spacer (int width) {
            var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            spacer.set_size_request (width, 1);
            spacer.sensitive = false;
            spacer.can_target = false;
            return spacer;
        }

        private void deferred_remove (Gtk.Widget widget) {
            widget.visible = false;
            Idle.add (() => {
                if (widget.get_parent () != null)
                    icon_box.remove (widget);
                return Source.REMOVE;
            });
        }

        // Remove all spacer widgets and cancel animations.
        private void remove_all_spacers () {
            if (gap_grow_anim != null) { gap_grow_anim.pause (); gap_grow_anim = null; }
            if (gap_shrink_anim != null) { gap_shrink_anim.pause (); gap_shrink_anim = null; }
            if (gap_spacer != null) {
                deferred_remove (gap_spacer);
                gap_spacer = null;
            }
            if (gap_spacer_old != null) {
                deferred_remove (gap_spacer_old);
                gap_spacer_old = null;
            }
            drop_gap_index = -1;
        }

        // ── Pin / reorder / unpin ───────────────────────────────

        private void pin_app (string desktop_id) {
            var pinned = app.config.pinned_apps;
            if (pinned == null) {
                pinned = new GenericArray<string> ();
            }
            for (uint i = 0; i < pinned.length; i++) {
                if (pinned[i] == desktop_id) return;
            }
            pinned.add (desktop_id);
            app.config.pinned_apps = pinned;
            app.config.save ();
            populate_icons ();
            update_indicators ();
        }

        private void reorder_pinned_at (string source_id, int insert_visual_index) {
            var pinned = app.config.pinned_apps;
            if (pinned == null) pinned = new GenericArray<string> ();

            // Remove source if already pinned
            int src_idx = -1;
            for (uint i = 0; i < pinned.length; i++) {
                if (pinned[i] == source_id) { src_idx = (int) i; break; }
            }
            if (src_idx >= 0) {
                pinned.remove_index (src_idx);
            }

            // Clamp and insert
            int pos = insert_visual_index;
            if (pos > (int) pinned.length) pos = (int) pinned.length;
            pinned.insert (pos, source_id);

            app.config.pinned_apps = pinned;
            app.config.save ();
            populate_icons ();
            update_indicators ();
        }

        private void unpin_app (string desktop_id) {
            var new_pinned = new GenericArray<string> ();
            var pinned = app.config.pinned_apps;
            if (pinned == null) return;
            for (uint i = 0; i < pinned.length; i++) {
                if (pinned[i] != desktop_id) {
                    new_pinned.add (pinned[i]);
                }
            }
            app.config.pinned_apps = new_pinned;
            app.config.save ();
            populate_icons ();
        }

        private void schedule_hide () {
            cancel_hide ();
            hide_timeout_id = Timeout.add (HIDE_DELAY_MS, () => {
                hide_timeout_id = 0;
                int64 now = GLib.get_monotonic_time () / 1000;
                if ((now - show_timestamp) < SHOW_GRACE_MS) return Source.REMOVE;
                bool on_trigger = linked_trigger != null && linked_trigger.cursor_on_trigger;
                if (cursor_inside || on_trigger || popover_open || dnd_active) return Source.REMOVE;
                hide_animated ();
                return Source.REMOVE;
            });
        }

        private void cancel_hide () {
            if (hide_timeout_id != 0) {
                Source.remove (hide_timeout_id);
                hide_timeout_id = 0;
            }
        }
    }
}
