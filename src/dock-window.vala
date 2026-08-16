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

    public class DockWindow : Gtk.Window {

        public signal void grid_requested ();

        private weak Application app;
        public Gdk.Monitor? monitor { get; private set; }
        private int niri_logical_monitor_width = 0;
        private int niri_logical_monitor_height = 0;
        private Gtk.Box wave_surface;
        private Gtk.Box dock_content;
        private Gtk.Box main_box;
        private Gtk.Box icon_box;
        private Gtk.Separator running_separator;
        private Gtk.Box running_box;
        private Gtk.Separator folder_separator;
        private Gtk.Box folder_box;
        private Gtk.Box trash_box;
        private FolderStackWindow? folder_stack_window;
        private DockItemGapController app_drag_gaps;
        private DockItemGapController folder_drag_gaps;
        // The compositor reports focus changes much more often than the set
        // of running applications changes. Keep this separate so focus does
        // not recreate icons or make the dock choose an icon size again.
        private string running_icons_signature = "";
        private GridWaveIcon grid_wrapper;
        private Gtk.Button grid_button;
        private Gtk.Image grid_image;
        private bool autohide_enabled = false;
        private bool popover_open = false;
        private bool dnd_active = false;
        private bool item_drag_active = false;
        private bool external_drag_active = false;
        private uint external_drag_end_id = 0;
        private bool cursor_inside = false;
        private uint hide_timeout_id = 0;
        private uint watchdog_id = 0;
        // Invalidates a completed fade-out after autohide has been disabled
        // or the dock was shown again while that animation was in flight.
        private uint visibility_animation_generation = 0;
        private uint magnification_tick_id = 0;
        private int64 magnification_last_frame_time = 0;
        private double wave_focus_x = 0.0;
        private double wave_target_x = 0.0;
        private double wave_strength = 0.0;
        private double wave_target_strength = 0.0;
        private double wave_pointer_x = 0.0;
        private double wave_pointer_y = 0.0;
        private GenericArray<WaveIconState>? active_wave_icons;
        private Gtk.Widget? magnified_drag_item;
        private DockItemGapController? magnified_drag_gaps;
        private Gdk.Paintable? magnified_drag_paintable;
        private int magnified_drag_width = 0;
        private int magnified_drag_height = 0;
        private weak DockTrigger? linked_trigger = null;
        private int64 show_timestamp = 0;
        private int64 leave_timestamp = 0;

        private int DOCK_HEIGHT = 64;
        private int effective_icon_size = 48;
        private int floating_surface_left_margin = 0;
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

            LayerShellHelper.setup_dock_floating (
                this, app.config.floating_margin, LayerShellHelper.parse_layer (app.config.layer),
                app.config.dock_position
            );
            if (monitor != null) {
                GtkLayerShell.set_monitor (this, monitor);
                monitor.notify["geometry"].connect (() => {
                    refresh_niri_logical_monitor_width ();
                    update_icon_sizes_to_fit ();
                });
            }
            apply_mode ();

            build_ui ();
            folder_stack_window = new FolderStackWindow (monitor);
            folder_stack_window.state_changed.connect ((open) => {
                popover_open = open;
                if (open) cancel_hide ();
                else if (autohide_enabled) schedule_hide ();
            });
            populate_icons ();
            apply_position ();

            app.config.notify["icon-size"].connect (() => {
                rebuild_dock ();
            });
            app.config.notify["show-trash"].connect (() => {
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
            app.config.notify["floating-margin"].connect (() => {
                if (app.config.dock_mode != DockMode.FLOATING) return;
                GtkLayerShell.Edge edge = GtkLayerShell.Edge.BOTTOM;
                if (app.config.dock_position == DockPosition.TOP) edge = GtkLayerShell.Edge.TOP;
                else if (app.config.dock_position == DockPosition.LEFT) edge = GtkLayerShell.Edge.LEFT;
                else if (app.config.dock_position == DockPosition.RIGHT) edge = GtkLayerShell.Edge.RIGHT;
                GtkLayerShell.set_margin (this, edge, app.config.floating_margin);
                if (linked_trigger != null)
                    linked_trigger.set_edge_margin (app.config.floating_margin);
            });

            var motion = new Gtk.EventControllerMotion ();
            motion.leave.connect (() => {
                cursor_inside = false;
                clear_magnified_hover ();
                reset_icon_magnification ();
                leave_timestamp = GLib.get_monotonic_time () / 1000;
                if (autohide_enabled && !popover_open && !dnd_active) {
                    schedule_hide ();
                }
            });
            motion.enter.connect ((x, y) => {
                cursor_inside = true;
                wave_pointer_x = x;
                wave_pointer_y = y;
                show_timestamp = GLib.get_monotonic_time () / 1000;
                cancel_hide ();
            });
            motion.motion.connect ((x, y) => {
                wave_pointer_x = x;
                wave_pointer_y = y;
                update_icon_magnification (app.config.dock_position.is_vertical () ? y : x);
            });
            ((Gtk.Widget) this).add_controller (motion);

            var magnified_click = new Gtk.GestureClick ();
            magnified_click.button = Gdk.BUTTON_PRIMARY;
            magnified_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            magnified_click.released.connect ((n_press, x, y) => {
                if (active_wave_icons == null) return;
                for (uint i = 0; i < active_wave_icons.length; i++) {
                    if (active_wave_icons[i].activate_if_visual_only (x, y)) break;
                }
            });
            ((Gtk.Widget) this).add_controller (magnified_click);

            var magnified_drag = new Gtk.DragSource ();
            magnified_drag.set_actions (Gdk.DragAction.MOVE);
            magnified_drag.prepare.connect ((x, y) => {
                if (active_wave_icons == null) return null;
                for (uint i = 0; i < active_wave_icons.length; i++) {
                    string? source_id;
                    if (!active_wave_icons[i].prepare_drag_if_visual_only (x, y, out source_id)) {
                        continue;
                    }
                    magnified_drag_item = active_wave_icons[i].get_widget ();
                    magnified_drag_paintable = active_wave_icons[i].create_drag_paintable (
                        out magnified_drag_width, out magnified_drag_height
                    );
                    return new Gdk.ContentProvider.for_value (source_id);
                }
                return null;
            });
            magnified_drag.drag_begin.connect ((drag) => {
                if (magnified_drag_item == null) return;
                if (magnified_drag_paintable != null) {
                    magnified_drag.set_icon (
                        magnified_drag_paintable,
                        magnified_drag_width / 2,
                        magnified_drag_height / 2
                    );
                }
                item_drag_active = true;
                update_dnd_active ();
                reset_icon_magnification ();
                cancel_hide ();
                if (magnified_drag_item is DockIcon) {
                    magnified_drag_gaps = app_drag_gaps;
                } else {
                    magnified_drag_gaps = folder_drag_gaps;
                }
                magnified_drag_gaps.begin (magnified_drag_item);
            });
            magnified_drag.drag_end.connect ((drag, del) => {
                if (magnified_drag_gaps != null) magnified_drag_gaps.finish ();
                magnified_drag_gaps = null;
                magnified_drag_item = null;
                magnified_drag_paintable = null;
                item_drag_active = false;
                update_dnd_active ();
                if (autohide_enabled && !external_drag_active) schedule_hide ();
            });
            ((Gtk.Widget) this).add_controller (magnified_drag);
        }

        public void set_trigger (DockTrigger trigger) {
            this.linked_trigger = trigger;
        }

        public void apply_mode () {
            GtkLayerShell.set_layer (this, LayerShellHelper.parse_layer (app.config.layer));
            // DOCK_HEIGHT includes transparent headroom for hover
            // magnification and launch bounce.  It must keep the layer
            // surface large enough to draw those effects, but reserving that
            // headroom pushes regular windows away from the dock.  Reserve
            // only the physical dock bar so animated icons may overlap
            // window content above it.
            LayerShellHelper.apply_dock_mode (
                this, app.config.dock_mode, get_exclusive_zone_height (),
                app.config.floating_margin, app.config.dock_position
            );
            if (app.config.dock_mode == DockMode.PINNED)
                floating_surface_left_margin = 0;
            if (get_child () != null) {
                dock_content.hexpand = app.config.dock_mode == DockMode.PINNED &&
                    !app.config.dock_position.is_vertical ();
                dock_content.vexpand = app.config.dock_mode == DockMode.PINNED &&
                    app.config.dock_position.is_vertical ();
            }
        }

        public void apply_position () {
            reset_icon_magnification ();
            var orientation = app.config.dock_position.orientation ();
            main_box.orientation = orientation;
            icon_box.orientation = orientation;
            running_box.orientation = orientation;
            folder_box.orientation = orientation;
            trash_box.orientation = orientation;
            running_separator.orientation = app.config.dock_position.is_vertical ()
                ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
            folder_separator.orientation = running_separator.orientation;
            grid_wrapper.apply_position (app.config.dock_position);
            app_drag_gaps.set_orientation (orientation);
            folder_drag_gaps.set_orientation (orientation);
            update_box_positions (icon_box);
            update_box_positions (running_box);
            update_box_positions (folder_box);
            update_box_positions (trash_box);
            dock_content.orientation = app.config.dock_position.is_vertical ()
                ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
            wave_surface.orientation = dock_content.orientation;
            if (!app.config.dock_position.is_vertical ()) {
                var edge_align = app.config.dock_position == DockPosition.TOP
                    ? Gtk.Align.START : Gtk.Align.END;
                dock_content.halign = Gtk.Align.CENTER; dock_content.valign = edge_align;
                wave_surface.halign = Gtk.Align.CENTER; wave_surface.valign = edge_align;
            } else {
                var edge_align = app.config.dock_position == DockPosition.LEFT
                    ? Gtk.Align.START : Gtk.Align.END;
                dock_content.halign = edge_align; dock_content.valign = Gtk.Align.CENTER;
                wave_surface.halign = edge_align; wave_surface.valign = Gtk.Align.CENTER;
            }
            remove_css_class ("position-bottom");
            remove_css_class ("position-top");
            remove_css_class ("position-left");
            remove_css_class ("position-right");
            add_css_class ("position-" + app.config.dock_position.to_string ());
            set_axis_margins (main_box, 0, 0);
            set_axis_margins (wave_surface, 0, 0);
            if (folder_stack_window != null)
                folder_stack_window.apply_position (app.config.dock_position);
            set_size_request (-1, -1);
            apply_mode ();
            update_icon_sizes_to_fit ();
            queue_resize ();
        }

        private void update_box_positions (Gtk.Box box) {
            var child = box.get_first_child ();
            while (child != null) {
                if (child is DockIcon) ((DockIcon) child).apply_position (app.config.dock_position);
                else if (child is FolderDockIcon) ((FolderDockIcon) child).apply_position (app.config.dock_position);
                else if (child is TrashDockIcon) ((TrashDockIcon) child).apply_position (app.config.dock_position);
                child = child.get_next_sibling ();
            }
        }

        public void enable_autohide (bool enabled) {
            autohide_enabled = enabled;
            if (!enabled) {
                visibility_animation_generation++;
                cancel_hide ();
                if (watchdog_id != 0) { Source.remove (watchdog_id); watchdog_id = 0; }
                set_visible (true);
            } else {
                if (watchdog_id == 0) {
                    watchdog_id = Timeout.add (400, () => {
                        bool on_trigger = linked_trigger != null && linked_trigger.cursor_on_trigger;
                        int64 now = GLib.get_monotonic_time () / 1000;
                        bool in_show_grace = (now - show_timestamp) < SHOW_GRACE_MS;
                        bool in_leave_grace = (now - leave_timestamp) < app.config.hide_delay;
                        if (visible && !cursor_inside && !on_trigger && !popover_open && !dnd_active && autohide_enabled && !is_active_workspace_empty () && !in_show_grace && !in_leave_grace) {
                            hide_animated ();
                        }
                        return Source.CONTINUE;
                    });
                }
            }
        }

        public void show_animated () {
            cancel_hide ();
            visibility_animation_generation++;
            show_timestamp = GLib.get_monotonic_time () / 1000;
            set_visible (true);
            opacity = 0;

            var target = new Adw.PropertyAnimationTarget (this, "opacity");
            var anim = new Adw.TimedAnimation (this, 0.0, 1.0, 200, target);
            anim.play ();
        }

        // The trigger fills the configured margin, so a floating dock can
        // stay offset from the edge without creating a pointer input gap.
        public void reveal_from_trigger () {
            if (app.config.dock_mode != DockMode.FLOATING) return;
            cancel_hide ();
            visibility_animation_generation++;
            show_timestamp = GLib.get_monotonic_time () / 1000;

            if (!visible) {
                set_visible (true);
                opacity = 0;

                var target = new Adw.PropertyAnimationTarget (this, "opacity");
                var anim = new Adw.TimedAnimation (this, 0.0, 1.0, 200, target);
                anim.play ();
            } else {
                // A previous hide animation may have made the dock mostly
                // transparent even though its surface is still visible.
                opacity = 1;
            }
        }

        public void hide_animated () {
            cursor_inside = false;
            uint generation = ++visibility_animation_generation;
            var target = new Adw.PropertyAnimationTarget (this, "opacity");
            var anim = new Adw.TimedAnimation (this, 1.0, 0.0, 200, target);
            anim.done.connect (() => {
                if (generation != visibility_animation_generation || !autohide_enabled) return;
                set_visible (false);
                opacity = 1;
                if (app.config.dock_mode == DockMode.FLOATING) {
                    GtkLayerShell.Edge edge = GtkLayerShell.Edge.BOTTOM;
                    if (app.config.dock_position == DockPosition.TOP) edge = GtkLayerShell.Edge.TOP;
                    else if (app.config.dock_position == DockPosition.LEFT) edge = GtkLayerShell.Edge.LEFT;
                    else if (app.config.dock_position == DockPosition.RIGHT) edge = GtkLayerShell.Edge.RIGHT;
                    GtkLayerShell.set_margin (this, edge, app.config.floating_margin);
                }
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
                    icon.set_running (tracker.is_running_app (icon.app_entry));
                    icon.set_window_count (tracker.windows_for_app (icon.app_entry).length);
                    icon.set_focused (tracker.is_focused_app (icon.app_entry));
                }
                child = child.get_next_sibling ();
            }

            // Build a stable description of the unpinned running entries.
            // A focus-only event must not tear down and rebuild this box.
            var shown_classes = new GenericArray<string> ();
            var desired_entries = new GenericArray<AppEntry> ();
            var signature = new StringBuilder ();

            // Collect application entries already represented by dock icons.
            var dock_items = app.config.dock_items;
            for (uint i = 0; i < dock_items.length; i++) {
                if (ConfigManager.is_app_item (dock_items[i]))
                    shown_classes.add (ConfigManager.item_desktop_id (dock_items[i]));
            }

            // Collect running apps not already represented by a pinned icon.
            for (uint i = 0; i < tracker.running_apps.length; i++) {
                var running = tracker.running_apps[i];
                bool already_shown = false;

                for (uint j = 0; j < shown_classes.length; j++) {
                    var shown_entry = find_entry_by_desktop_id (shown_classes[j]);
                    if (shown_entry != null &&
                        shown_entry.matches_window_class (running.app_class)) {
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

                    var entry = find_entry_by_class (running.app_class);
                    if (entry != null) {
                        desired_entries.add (entry);
                        signature.append (entry.desktop_id);
                        signature.append_c ('\x1f');
                    }
                }
            }

            if (signature.str != running_icons_signature) {
                rebuild_running_icons (desired_entries);
                running_icons_signature = signature.str;
                update_icon_sizes_to_fit ();
            } else {
                update_running_icon_focus ();
            }
            update_workspace_visibility ();
        }

        private bool is_active_workspace_empty () {
            return monitor != null && app.window_tracker.is_active_workspace_empty (
                monitor.get_connector ()
            );
        }

        private void update_workspace_visibility () {
            if (app.config.dock_mode != DockMode.FLOATING || !autohide_enabled) return;
            if (is_active_workspace_empty ()) {
                cancel_hide ();
                // This path can run while monitor selection tears down and
                // recreates layer-shell surfaces. Avoid leaving a property
                // animation targeting a surface that is being destroyed.
                if (!visible) {
                    visibility_animation_generation++;
                    opacity = 1;
                    set_visible (true);
                }
            } else if (visible && !cursor_inside && !popover_open && !dnd_active) {
                schedule_hide ();
            }
        }

        private void show_window_list (DockIcon icon) {
            var windows = app.window_tracker.windows_for_app (icon.app_entry);
            if (windows.length < 2) {
                app.window_tracker.focus_app (icon.app_entry);
                return;
            }

            var popover = new Gtk.Popover ();
            popover.set_parent (icon);
            popover.has_arrow = true;
            popover.position = app.config.dock_position.inward_popover_position ();
            popover.add_css_class ("menu");

            var list = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            for (uint i = 0; i < windows.length; i++) {
                var window = windows[i];
                var title = window.title.length > 0 ? window.title : icon.app_entry.name;
                if (window.workspace.length > 0)
                    title += " (" + window.workspace + ")";
                var item = new Gtk.Button.with_label (title);
                var target_window = window;
                item.add_css_class ("flat");
                item.halign = Gtk.Align.FILL;
                item.clicked.connect (() => {
                    popover.popdown ();
                    app.window_tracker.focus_window (target_window);
                });
                list.append (item);
            }
            popover.set_child (list);
            popover.closed.connect (() => {
                popover_open = false;
                popover.unparent ();
                if (autohide_enabled) schedule_hide ();
            });
            popover_open = true;
            cancel_hide ();
            popover.popup ();
        }

        private void rebuild_running_icons (GenericArray<AppEntry> entries) {
            var child = running_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                running_box.remove (child);
                child = next;
            }

            for (uint i = 0; i < entries.length; i++) {
                var icon = new DockIcon (entries[i], app.config.icon_size, false,
                                         app.config.bounce_on_launch,
                                         app.config.bounce_duration,
                                         app.config.dock_position);
                icon.set_running (true);
                icon.set_window_count (app.window_tracker.windows_for_app (icon.app_entry).length);
                icon.set_focused (app.window_tracker.is_focused_app (icon.app_entry));
                icon.pin_requested.connect ((id) => { pin_app (id); });
                icon.focus_requested.connect ((id) => {
                    app.window_tracker.focus_app (icon.app_entry);
                });
                icon.windows_requested.connect ((source) => {
                    show_window_list (source);
                });
                icon.close_requested.connect ((id) => {
                    app.window_tracker.close_app (icon.app_entry);
                });
                icon.popover_state_changed.connect ((open) => {
                    popover_open = open;
                    if (open) cancel_hide ();
                    else if (autohide_enabled) schedule_hide ();
                });
                running_box.append (icon);
            }
            bool has_running = entries.length > 0;
            running_box.visible = has_running;
            running_separator.visible = has_running && icon_box.get_first_child () != null;
        }

        private void update_running_icon_focus () {
            var child = running_box.get_first_child ();
            while (child != null) {
                if (child is DockIcon) {
                    var icon = (DockIcon) child;
                    icon.set_running (true);
                    icon.set_window_count (app.window_tracker.windows_for_app (icon.app_entry).length);
                    icon.set_focused (app.window_tracker.is_focused_app (icon.app_entry));
                }
                child = child.get_next_sibling ();
            }
        }

        private AppEntry? find_entry_by_class (string app_class) {
            var apps = app.app_provider.apps;
            if (apps == null) return null;
            for (uint i = 0; i < apps.length; i++) {
                if (apps[i].matches_window_class (app_class)) return apps[i];
            }
            return null;
        }

        private AppEntry? find_entry_by_desktop_id (string desktop_id) {
            var apps = app.app_provider.apps;
            if (apps == null) return null;
            for (uint i = 0; i < apps.length; i++) {
                if (apps[i].desktop_id == desktop_id) return apps[i];
            }
            return null;
        }

        private void build_ui () {
            var main_box = new Gtk.Box (app.config.dock_position.orientation (), 2);
            this.main_box = main_box;
            main_box.halign = Gtk.Align.CENTER;
            main_box.valign = Gtk.Align.CENTER;

            // Grid button — same structure as DockIcon
            grid_wrapper = new GridWaveIcon (app.config.dock_position);

            grid_button = new Gtk.Button ();
            grid_button.add_css_class ("dock-icon");
            grid_button.add_css_class ("flat");
            grid_image = new Gtk.Image.from_icon_name ("view-app-grid-symbolic");
            grid_image.pixel_size = app.config.icon_size;
            grid_button.set_child (grid_image);
            grid_button.tooltip_text = _("Applications");
            grid_button.clicked.connect (() => {
                grid_requested ();
            });
            grid_wrapper.append (grid_button);
            grid_wrapper.set_input_button (grid_button);

            // Match DockIcon indicator_box height
            var grid_indicator = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            grid_indicator.add_css_class ("dock-indicator-box");
            grid_wrapper.append (grid_indicator);

            // Pinned icons
            icon_box = new Gtk.Box (app.config.dock_position.orientation (), 2);
            icon_box.overflow = Gtk.Overflow.VISIBLE;

            // Running (not pinned) icons
            running_separator = new Gtk.Separator (app.config.dock_position.is_vertical ()
                ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL);
            running_separator.add_css_class ("dock-separator");
            running_separator.visible = false;

            running_box = new Gtk.Box (app.config.dock_position.orientation (), 2);
            running_box.overflow = Gtk.Overflow.VISIBLE;
            running_box.visible = false;

            folder_separator = new Gtk.Separator (app.config.dock_position.is_vertical ()
                ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL);
            folder_separator.add_css_class ("dock-separator");
            folder_separator.visible = false;

            folder_box = new Gtk.Box (app.config.dock_position.orientation (), 2);
            folder_box.overflow = Gtk.Overflow.VISIBLE;
            folder_box.visible = false;

            trash_box = new Gtk.Box (app.config.dock_position.orientation (), 2);
            trash_box.overflow = Gtk.Overflow.VISIBLE;
            trash_box.visible = false;

            app_drag_gaps = new DockItemGapController (
                icon_box, get_spacer_width (), (widget) => widget is DockIcon,
                app.config.dock_position.orientation ()
            );
            folder_drag_gaps = new DockItemGapController (
                folder_box, get_spacer_width (), (widget) => widget is FolderDockIcon,
                app.config.dock_position.orientation ()
            );

            main_box.append (grid_wrapper);
            main_box.append (icon_box);
            main_box.append (running_separator);
            main_box.append (running_box);
            main_box.append (folder_separator);
            main_box.append (folder_box);
            main_box.append (trash_box);

            dock_content = new Gtk.Box (app.config.dock_position.is_vertical ()
                ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL, 0);
            dock_content.add_css_class ("dock-content");
            dock_content.halign = Gtk.Align.CENTER;
            dock_content.valign = Gtk.Align.END;
            dock_content.hexpand = app.config.dock_mode == DockMode.PINNED &&
                !app.config.dock_position.is_vertical ();
            dock_content.vexpand = app.config.dock_mode == DockMode.PINNED &&
                app.config.dock_position.is_vertical ();
            dock_content.append (main_box);

            wave_surface = new Gtk.Box (app.config.dock_position.is_vertical ()
                ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL, 0);
            wave_surface.halign = Gtk.Align.CENTER;
            wave_surface.valign = Gtk.Align.END;
            wave_surface.append (dock_content);

            // DropTarget on icon_box — reorder with animated spacer gap
            var icon_drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            icon_drop.motion.connect ((x, y) => {
                // A string from Launcher or another application must fall
                // through to the dock-wide target.  This target is reserved
                // strictly for rearranging an item already dragged from Dock.
                if (!item_drag_active || drop_contains_file_list (icon_drop)) {
                    app_drag_gaps.clear ();
                    return (Gdk.DragAction) 0;
                }
                app_drag_gaps.move_to (app_drag_gaps.compute_insert_index (app.config.dock_position.is_vertical () ? y : x));
                return Gdk.DragAction.MOVE;
            });
            icon_drop.leave.connect (() => {
                if (item_drag_active) app_drag_gaps.restore_source_gap ();
            });
            icon_drop.drop.connect ((val, x, y) => {
                if (!item_drag_active || drop_contains_file_list (icon_drop)) {
                    app_drag_gaps.clear ();
                    return false;
                }
                var source_id = (string) val;
                if (source_id == null || ConfigManager.is_folder_item (source_id) ||
                    !is_known_app_drop (source_id)) return false;
                int idx = app_drag_gaps.compute_insert_index (app.config.dock_position.is_vertical () ? y : x);
                app_drag_gaps.clear ();
                reorder_dock_item_at (normalize_drop_item (source_id), idx);
                return true;
            });
            icon_box.add_controller (icon_drop);

            var folder_drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            folder_drop.motion.connect ((x, y) => {
                if (!item_drag_active || drop_contains_file_list (folder_drop)) {
                    folder_drag_gaps.clear ();
                    return (Gdk.DragAction) 0;
                }
                folder_drag_gaps.move_to (folder_drag_gaps.compute_insert_index (app.config.dock_position.is_vertical () ? y : x));
                return Gdk.DragAction.MOVE;
            });
            folder_drop.leave.connect (() => {
                if (item_drag_active) folder_drag_gaps.restore_source_gap ();
            });
            folder_drop.drop.connect ((val, x, y) => {
                if (!item_drag_active || drop_contains_file_list (folder_drop)) {
                    folder_drag_gaps.clear ();
                    return false;
                }
                var source_id = (string) val;
                if (source_id == null || !ConfigManager.is_folder_item (source_id)) return false;
                var path = ConfigManager.item_folder_path (source_id);
                if (!FileUtils.test (path, FileTest.IS_DIR)) return false;
                int position = folder_drag_gaps.compute_insert_index (app.config.dock_position.is_vertical () ? y : x);
                folder_drag_gaps.clear ();
                app.reorder_dock_folder (path, position);
                return true;
            });
            folder_box.add_controller (folder_drop);

            // The dock-wide fallback accepts external app drags everywhere on
            // the visible dock, including its padding.  Item boxes above
            // claim only drags whose source is another Dock item.
            var dock_drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
            dock_drop.motion.connect ((x, y) => {
                set_external_drag_active (true);
                return Gdk.DragAction.MOVE;
            });
            dock_drop.leave.connect (() => { schedule_external_drag_end (); });
            dock_drop.drop.connect ((val, x, y) => {
                schedule_external_drag_end ();
                if (drop_contains_file_list (dock_drop)) return false;
                var source_id = (string) val;
                if (source_id == null || !is_known_app_drop (source_id)) return false;
                add_drop_item (normalize_drop_item (source_id));
                return true;
            });
            dock_content.add_controller (dock_drop);

            // DnD does not bubble from a child DropTarget to its parent.
            // Register the native file target on each folder-accepting visual
            // zone, so users can drop a folder anywhere among dock items.
            // TrashDockIcon intentionally owns its area exclusively: a file
            // dropped there must be moved to Trash, never added as a Stack.
            setup_file_drop_target (dock_content);
            setup_file_drop_target (grid_wrapper);
            setup_file_drop_target (icon_box);
            setup_file_drop_target (running_box);
            setup_file_drop_target (folder_box);

            set_child (wave_surface);

            setup_dock_context_menu (main_box);
        }

        // Keep file-manager DnD separate from the string protocol used by
        // DockIcon and Launcher.  A file list has to be handled exclusively
        // by file_drop, never by an app reorder or pin target.
        private bool drop_contains_file_list (Gtk.DropTarget target) {
            var drop = target.get_current_drop ();
            return drop != null &&
                drop.get_formats ().contain_gtype (typeof (Gdk.FileList));
        }

        private void setup_file_drop_target (Gtk.Widget target, int insert_folder_position = -1) {
            var file_drop = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            file_drop.motion.connect ((x, y) => {
                set_external_drag_active (true);
                return Gdk.DragAction.COPY;
            });
            file_drop.leave.connect (() => { schedule_external_drag_end (); });
            file_drop.drop.connect ((val, x, y) => {
                schedule_external_drag_end ();
                var files = (Gdk.FileList) val;
                foreach (var file in files.get_files ()) {
                    if (file.query_file_type (FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
                        add_folder_file (file, insert_folder_position);
                        return true;
                    }
                }
                return false;
            });
            target.add_controller (file_drop);
        }

        private bool is_known_app_drop (string source_id) {
            if (ConfigManager.is_folder_item (source_id)) return false;
            var desktop_id = ConfigManager.is_app_item (source_id)
                ? ConfigManager.item_desktop_id (source_id) : source_id;
            return desktop_id.length > 0 &&
                app.app_provider.find_by_desktop_id (desktop_id) != null;
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
            popover.position = app.config.dock_position.inward_popover_position ();
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

            var settings_btn = new Gtk.Button.with_label (_("Settings"));
            settings_btn.add_css_class ("flat");
            settings_btn.halign = Gtk.Align.FILL;
            settings_btn.clicked.connect (() => {
                popover.popdown ();
                open_settings ();
            });
            menu_box.append (settings_btn);

            var folder_btn = new Gtk.Button.with_label (_("Add Folder…"));
            folder_btn.add_css_class ("flat");
            folder_btn.halign = Gtk.Align.FILL;
            folder_btn.clicked.connect (() => {
                popover.popdown ();
                choose_folder ();
            });
            menu_box.append (folder_btn);

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

        private void choose_folder () {
            try {
                var connection = Bus.get_sync (BusType.SESSION, null);
                var options = new VariantBuilder (new VariantType ("a{sv}"));
                options.add ("{sv}", "directory", new Variant.boolean (true));
                options.add ("{sv}", "multiple", new Variant.boolean (false));
                options.add ("{sv}", "modal", new Variant.boolean (true));
                options.add ("{sv}", "accept_label", new Variant.string (_("Add Folder")));

                // A layer-shell surface cannot safely parent a GTK dialog.
                // The portal owns its own regular surface; an empty parent
                // handle is the supported fallback for this surface type.
                var reply = connection.call_sync (
                    "org.freedesktop.portal.Desktop",
                    "/org/freedesktop/portal/desktop",
                    "org.freedesktop.portal.FileChooser",
                    "OpenFile",
                    new Variant ("(ss@a{sv})", "", _("Add Folder to Dock"), options.end ()),
                    new VariantType ("(o)"),
                    DBusCallFlags.NONE, -1, null
                );
                var request_path = reply.get_child_value (0).get_string ();
                uint subscription_id = 0;
                subscription_id = connection.signal_subscribe (
                    "org.freedesktop.portal.Desktop",
                    "org.freedesktop.portal.Request",
                    "Response",
                    request_path,
                    null,
                    DBusSignalFlags.NONE,
                    (conn, sender, object_path, interface_name, signal_name, parameters) => {
                        conn.signal_unsubscribe (subscription_id);
                        if (parameters.get_child_value (0).get_uint32 () != 0) return;

                        var results = parameters.get_child_value (1);
                        var result_iter = results.iterator ();
                        string key;
                        Variant value;
                        while (result_iter.next ("{sv}", out key, out value)) {
                            if (key != "uris") continue;
                            // a{sv} values are variant-wrapped. The portal
                            // returns uris as an array of strings inside it.
                            var uris = value;
                            if (uris.is_of_type (VariantType.VARIANT))
                                uris = uris.get_variant ();
                            if (!uris.is_of_type (VariantType.STRING_ARRAY)) {
                                warning ("Folder chooser returned invalid uris");
                                return;
                            }
                            var selected = uris.get_strv ();
                            if (selected.length == 0) return;
                            add_folder_file (File.new_for_uri (selected[0]));
                            return;
                        }
                    }
                );
            } catch (Error e) {
                warning ("Failed to open folder chooser portal: %s", e.message);
            }
        }

        private void add_folder_file (File folder, int insert_folder_position = -1) {
            var path = folder.get_path ();
            if (path == null || !FileUtils.test (path, FileTest.IS_DIR)) return;
            if (insert_folder_position >= 0) {
                app.add_dock_folder_at (path, insert_folder_position);
            } else {
                app.add_dock_folder (path);
            }
        }

        public void rebuild_dock () {
            DOCK_HEIGHT = app.config.icon_size + 12;
            populate_icons ();
            running_icons_signature = "";
            update_indicators ();
            apply_mode ();
            queue_resize ();
        }

        private int get_axis_margin (Gtk.Widget widget, bool start) {
            if (app.config.dock_position.is_vertical ())
                return start ? widget.margin_top : widget.margin_bottom;
            return start ? widget.margin_start : widget.margin_end;
        }

        private void set_axis_margins (Gtk.Widget widget, int start, int end) {
            if (app.config.dock_position.is_vertical ()) {
                widget.margin_top = start; widget.margin_bottom = end;
                widget.margin_start = 0; widget.margin_end = 0;
            } else {
                widget.margin_start = start; widget.margin_end = end;
                widget.margin_top = 0; widget.margin_bottom = 0;
            }
        }

        // The configured size is an upper bound.  Floating layer-shell
        // surfaces are sized from their natural width, so GTK cannot shrink
        // this box for us when it grows wider than its monitor.
        private void update_icon_sizes_to_fit () {
            int available_width = get_available_width ();
            if (available_width <= 0) return;

            int previous_size = effective_icon_size;
            int previous_reserve = get_axis_margin (wave_surface, true);
            int previous_height = DOCK_HEIGHT;
            int minimum = 0;
            int natural = 0;

            // Natural width grows monotonically with icon size. A binary
            // search avoids resizing every child once for every pixel between
            // the configured and minimum sizes when the dock is too narrow.
            int low = MIN_ICON_SIZE;
            int high = app.config.icon_size;
            int size = MIN_ICON_SIZE;
            int best = MIN_ICON_SIZE;
            bool fits = false;
            while (low <= high) {
                size = low + (high - low) / 2;
                set_effective_icon_size (size);
                int reserve = get_wave_horizontal_reserve ();
                set_axis_margins (wave_surface, reserve, reserve);
                wave_surface.measure (app.config.dock_position.orientation (), -1,
                                      out minimum, out natural, null, null);
                if (natural <= available_width) {
                    fits = true;
                    best = size;
                    low = size + 1;
                } else {
                    high = size - 1;
                }
            }

            size = fits ? best : MIN_ICON_SIZE;
            set_effective_icon_size (size);
            int reserve = get_wave_horizontal_reserve ();
            set_axis_margins (wave_surface, reserve, reserve);
            wave_surface.measure (app.config.dock_position.orientation (), -1,
                              out minimum, out natural, null, null);
            if (natural > available_width) {
                warning ("Dock contents exceed monitor width even at minimum icon size (%dpx)",
                         MIN_ICON_SIZE);
            }
            center_floating_surface (natural);
            int height = get_dock_height ();
            if (DOCK_HEIGHT != height) {
                DOCK_HEIGHT = height;
                apply_mode ();
            }
            // apply_position() clears the previous size request while
            // switching axes. Restore it even when the calculated extent is
            // unchanged, otherwise GTK allocates only the bar and clips the
            // transparent headroom used by magnified icons.
            set_size_request (app.config.dock_position.is_vertical () ? DOCK_HEIGHT : -1,
                              app.config.dock_position.is_vertical () ? -1 : DOCK_HEIGHT);
            if (wave_strength < 0.002) {
                set_axis_margins (main_box, 0, 0);
            }
            if (effective_icon_size != previous_size ||
                reserve != previous_reserve || DOCK_HEIGHT != previous_height) {
                queue_resize ();
            }
        }

        private int get_available_width () {
            int width = get_monitor_width ();
            if (width <= 0) return 0;
            if (app.config.dock_mode == DockMode.FLOATING) {
                width -= FLOATING_SIDE_MARGIN * 2;
            }
            return width;
        }

        private int get_monitor_width () {
            if (monitor == null) return 0;
            // GDK's Wayland monitor geometry may expose the pre-transform
            // mode width. Niri reports the actual logical output size, which
            // matters for portrait displays.
            if (app.config.dock_position.is_vertical ())
                return niri_logical_monitor_height > 0
                    ? niri_logical_monitor_height : monitor.geometry.height;
            return niri_logical_monitor_width > 0
                ? niri_logical_monitor_width : monitor.geometry.width;
        }

        // A floating layer surface with neither horizontal anchor is placed
        // at compositor discretion. Keep both anchors and set equal margins
        // so width changes stay centred on the selected monitor.
        private void center_floating_surface (int content_width) {
            if (app.config.dock_mode != DockMode.FLOATING) return;
            int monitor_width = get_monitor_width ();
            if (monitor_width <= 0) return;
            int side_margin = int.max ((monitor_width - content_width) / 2, 0);
            floating_surface_left_margin = side_margin;
            if (app.config.dock_position.is_vertical ()) {
                GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, side_margin);
                GtkLayerShell.set_margin (this, GtkLayerShell.Edge.BOTTOM, side_margin);
            } else {
                GtkLayerShell.set_margin (this, GtkLayerShell.Edge.LEFT, side_margin);
                GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, side_margin);
            }
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

        private int get_exclusive_zone_height () {
            return effective_icon_size + 12;
        }

        private int get_wave_horizontal_reserve () {
            if (!app.config.magnify_on_hover || app.config.dock_mode != DockMode.FLOATING) {
                return 0;
            }
            double growth = (app.config.magnify_scale - 100) / 100.0;
            // A wave near an edge can push every affected icon to one side.
            // Reserve the complete span up front: changing layout margins in
            // response to the pointer changes the layer-surface width, which
            // makes some compositors grow it from the right edge.
            int affected_icons = (int) app.config.magnify_radius;
            if ((double) affected_icons < app.config.magnify_radius) affected_icons++;
            affected_icons++;
            double per_icon_growth = (effective_icon_size + 24) * growth + WAVE_ICON_GAP;
            return (int) (affected_icons * per_icon_growth + 0.5);
        }

        private void refresh_niri_logical_monitor_width () {
            niri_logical_monitor_width = 0;
            niri_logical_monitor_height = 0;
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
                if (logical != null && logical.has_member ("width"))
                    niri_logical_monitor_width = (int) logical.get_int_member ("width");
                if (logical != null && logical.has_member ("height"))
                    niri_logical_monitor_height = (int) logical.get_int_member ("height");
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
            update_box_icon_sizes (folder_box, size);
            update_box_icon_sizes (trash_box, size);
        }

        private void update_box_icon_sizes (Gtk.Box box, int size) {
            var child = box.get_first_child ();
            while (child != null) {
                if (child is DockIcon) {
                    ((DockIcon) child).update_icon_size (size);
                } else if (child is FolderDockIcon) {
                    ((FolderDockIcon) child).update_icon_size (size);
                } else if (child is TrashDockIcon) {
                    ((TrashDockIcon) child).update_icon_size (size);
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
                if (is_dock_item_widget (child)) collect_wave_item (child, icons);
                child = child.get_next_sibling ();
            }
        }

        private bool is_dock_item_widget (Gtk.Widget widget) {
            return widget is DockIcon || widget is FolderDockIcon || widget is TrashDockIcon;
        }

        private void collect_wave_item (Gtk.Widget widget, GenericArray<WaveIconState> icons) {
            Graphene.Rect bounds;
            if (!widget.compute_bounds (this, out bounds)) return;
            icons.add (new WaveIconState (widget, bounds, 1.0, app.config.dock_position));
        }

        private void apply_wave_layout () {
            int radius = (int) (effective_icon_size * app.config.magnify_radius);
            var icons = new GenericArray<WaveIconState> ();
            collect_wave_item (grid_wrapper, icons);
            collect_box_wave_items (icon_box, icons);
            collect_box_wave_items (running_box, icons);
            collect_box_wave_items (folder_box, icons);
            collect_box_wave_items (trash_box, icons);

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
                icons[i].visual_offset = icons[i].layout_offset - focus_offset;
                base_left = double.min (base_left, icons[i].center - icons[i].width / 2.0);
                base_right = double.max (base_right, icons[i].center + icons[i].width / 2.0);
                visual_left = double.min (visual_left,
                    icons[i].center - icons[i].width * icons[i].scale / 2.0 +
                    icons[i].visual_offset);
                visual_right = double.max (visual_right,
                    icons[i].center + icons[i].width * icons[i].scale / 2.0 +
                    icons[i].visual_offset);
            }

            // Grow the visible dock background to cover the enlarged wave,
            // then return it to its normal size as the animation settles.
            //
            // wave_surface reserves this space before hover begins. Consume
            // that transparent reserve as main_box grows, so the layer-shell
            // surface keeps a fixed width and its symmetric margins continue
            // to centre it even on narrow monitors.
            int needed_start = (int) (double.max (base_left - visual_left, 0.0) + 1.0);
            int needed_end = (int) (double.max (visual_right - base_right, 0.0) + 1.0);
            int reserve = get_wave_horizontal_reserve ();
            int surface_start = int.max (reserve - needed_start, 0);
            int surface_end = int.max (reserve - needed_end, 0);
            if (get_axis_margin (main_box, true) != needed_start ||
                get_axis_margin (main_box, false) != needed_end ||
                get_axis_margin (wave_surface, true) != surface_start ||
                get_axis_margin (wave_surface, false) != surface_end) {
                set_axis_margins (main_box, needed_start, needed_end);
                set_axis_margins (wave_surface, surface_start, surface_end);
                queue_resize ();
            }
            active_wave_icons = icons;
            update_magnified_hover (icons);
        }

        private void update_magnified_hover (GenericArray<WaveIconState> icons) {
            for (uint i = 0; i < icons.length; i++) {
                icons[i].set_magnified_hover (
                    cursor_inside && icons[i].contains_visual (wave_pointer_x, wave_pointer_y)
                );
            }
        }

        private void clear_magnified_hover () {
            if (active_wave_icons == null) return;
            for (uint i = 0; i < active_wave_icons.length; i++) {
                active_wave_icons[i].set_magnified_hover (false);
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
            child = folder_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                folder_box.remove (child);
                child = next;
            }
            child = trash_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                trash_box.remove (child);
                child = next;
            }
            app_drag_gaps.clear ();
            folder_drag_gaps.clear ();

            var items = app.config.dock_items;
            for (uint i = 0; i < items.length; i++) {
                if (ConfigManager.is_app_item (items[i])) {
                    var entry = app.app_provider.find_by_desktop_id (
                        ConfigManager.item_desktop_id (items[i])
                    );
                    if (entry == null) continue;
                    var icon = new DockIcon (entry, app.config.icon_size, true,
                                             app.config.bounce_on_launch,
                                             app.config.bounce_duration,
                                             app.config.dock_position);
                    icon.unpin_requested.connect ((id) => {
                        unpin_app (id);
                    });
                    icon.focus_requested.connect ((id) => {
                        app.window_tracker.focus_app (icon.app_entry);
                    });
                    icon.windows_requested.connect ((source) => {
                        show_window_list (source);
                    });
                    icon.close_requested.connect ((id) => {
                        app.window_tracker.close_app (icon.app_entry);
                    });
                    icon.popover_state_changed.connect ((open) => {
                        popover_open = open;
                        if (open) cancel_hide ();
                        else if (autohide_enabled) schedule_hide ();
                    });
                    icon.drag_state_changed.connect ((active) => {
                        item_drag_active = active;
                        update_dnd_active ();
                        if (active) {
                            reset_icon_magnification ();
                            app_drag_gaps.begin (icon);
                        } else {
                            app_drag_gaps.finish ();
                        }
                    });
                    icon_box.append (icon);
                }
            }

            var folders = app.config.dock_folders;
            for (uint i = 0; i < folders.length; i++) {
                var folder = new FolderDockIcon (folders[i], app.config.icon_size,
                                                 app.config.dock_position);
                int insert_folder_position = (int) i + 1;
                folder.remove_requested.connect ((folder_path) => {
                    remove_folder (folder_path);
                });
                folder.settings_requested.connect ((folder_path) => {
                    var config = app.config.find_folder (folder_path);
                    if (config == null) return;
                    var settings = new FolderSettingsWindow (app.config, config);
                    settings.changed.connect (() => {
                        if (folder_stack_window != null) folder_stack_window.close_stack ();
                        populate_icons ();
                        update_indicators ();
                    });
                    settings.present ();
                });
                folder.favorites_changed.connect (() => {
                    app.config.save ();
                    if (folder_stack_window != null)
                        folder_stack_window.refresh_folder (folder);
                });
                folder.stack_requested.connect ((icon) => {
                    open_folder_stack (icon);
                });
                folder.popover_state_changed.connect ((open) => {
                    popover_open = open;
                    if (open) cancel_hide ();
                    else if (autohide_enabled) schedule_hide ();
                });
                folder.drag_state_changed.connect ((active) => {
                    item_drag_active = active;
                    update_dnd_active ();
                    if (active) {
                        reset_icon_magnification ();
                        cancel_hide ();
                        folder_drag_gaps.begin (folder);
                    } else {
                        folder_drag_gaps.finish ();
                        if (autohide_enabled && !external_drag_active) schedule_hide ();
                    }
                });
                // A DropTarget on folder_box is not reached when the file
                // manager targets this child icon directly. Register the
                // native file target here so a dropped directory is inserted
                // immediately after the folder it was dropped onto.
                setup_file_drop_target (folder, insert_folder_position);
                folder_box.append (folder);
            }
            bool has_folders = folders.length > 0;
            folder_box.visible = has_folders;
            if (app.config.show_trash) {
                var trash = new TrashDockIcon (app.config.icon_size,
                                               app.config.dock_position);
                trash.popover_state_changed.connect ((open) => {
                    popover_open = open;
                    if (open) cancel_hide ();
                    else if (autohide_enabled) schedule_hide ();
                });
                trash.drag_state_changed.connect ((active) => {
                    if (active) set_external_drag_active (true);
                    else schedule_external_drag_end ();
                });
                trash_box.append (trash);
            }
            trash_box.visible = app.config.show_trash;
            folder_separator.visible = has_folders || app.config.show_trash;
            update_icon_sizes_to_fit ();
        }

        private void open_folder_stack (FolderDockIcon folder) {
            if (folder_stack_window == null) return;
            Graphene.Rect bounds;
            if (!folder.compute_bounds (this, out bounds)) return;

            int stack_extent = app.config.dock_position.is_vertical ()
                ? folder.get_stack_height () : folder.get_stack_width ();
            int monitor_extent = get_monitor_width ();
            int center = floating_surface_left_margin + (int) (
                app.config.dock_position.is_vertical ()
                    ? bounds.origin.y + bounds.size.height / 2.0f
                    : bounds.origin.x + bounds.size.width / 2.0f);
            int along = int.max (center - stack_extent / 2, 0);
            if (monitor_extent > 0)
                along = int.min (along, int.max (monitor_extent - stack_extent, 0));

            int edge_margin = get_exclusive_zone_height ();
            if (app.config.dock_mode == DockMode.FLOATING) edge_margin += 16;
            folder_stack_window.present_folder (folder, along, edge_margin);
        }

        // ── DnD gap management ──────────────────────────────────

        private int get_spacer_width () {
            return effective_icon_size + 8;
        }

        // ── Dock item persistence ───────────────────────────────

        private void pin_app (string desktop_id) {
            add_drop_item (ConfigManager.app_item (desktop_id));
        }

        private string normalize_drop_item (string source_id) {
            if (ConfigManager.is_folder_item (source_id)) return source_id;
            if (ConfigManager.is_app_item (source_id)) return source_id;
            return ConfigManager.app_item (source_id);
        }

        private void add_drop_item (string item) {
            if (ConfigManager.is_folder_item (item)) {
                var path = ConfigManager.item_folder_path (item);
                app.add_dock_folder (path);
                return;
            }
            app.add_dock_item (item);
        }

        private void reorder_dock_item_at (string item, int insert_visual_index) {
            if (ConfigManager.is_folder_item (item) &&
                !FileUtils.test (ConfigManager.item_folder_path (item), FileTest.IS_DIR)) return;
            app.reorder_dock_item (item, insert_visual_index);
        }

        private void remove_folder (string folder_path) {
            app.remove_dock_folder (folder_path);
        }

        private void unpin_app (string desktop_id) {
            app.remove_dock_item (ConfigManager.app_item (desktop_id));
        }

        private void schedule_hide () {
            cancel_hide ();
            hide_timeout_id = Timeout.add (app.config.hide_delay, () => {
                hide_timeout_id = 0;
                int64 now = GLib.get_monotonic_time () / 1000;
                if ((now - show_timestamp) < SHOW_GRACE_MS) return Source.REMOVE;
                bool on_trigger = linked_trigger != null && linked_trigger.cursor_on_trigger;
                if (cursor_inside || on_trigger || popover_open || dnd_active ||
                    is_active_workspace_empty ()) return Source.REMOVE;
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

        // A drop arriving from another application has no DockIcon drag
        // source, so it must participate in autohide explicitly. Delay the
        // reset until the next main-loop turn: GTK emits leave/enter while a
        // pointer crosses sibling targets during one continuous drag.
        private void set_external_drag_active (bool active) {
            if (active) {
                if (external_drag_end_id != 0) {
                    Source.remove (external_drag_end_id);
                    external_drag_end_id = 0;
                }
                external_drag_active = true;
                update_dnd_active ();
                cancel_hide ();
            }
        }

        private void schedule_external_drag_end () {
            if (external_drag_end_id != 0) return;
            external_drag_end_id = Idle.add (() => {
                external_drag_end_id = 0;
                external_drag_active = false;
                update_dnd_active ();
                if (autohide_enabled && !cursor_inside && !popover_open) schedule_hide ();
                return Source.REMOVE;
            });
        }

        private void update_dnd_active () {
            dnd_active = item_drag_active || external_drag_active;
        }
    }
}
