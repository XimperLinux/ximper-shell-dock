namespace XimperShellDock {

    public class DockWindow : Gtk.Window {

        public signal void grid_requested ();

        private weak Application app;
        private Gtk.Box icon_box;
        private Gtk.Box running_box;
        private Gtk.Button grid_button;
        private bool autohide_enabled = false;
        private bool popover_open = false;
        private bool dnd_active = false;
        private bool cursor_inside = false;
        private uint hide_timeout_id = 0;
        private uint watchdog_id = 0;
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
        private const int HIDE_DELAY_MS = 300;
        private const int SHOW_GRACE_MS = 600;

        public DockWindow (Application app, Gdk.Monitor? monitor = null) {
            this.app = app;
            this.title = "Ximper Shell Dock";
            this.decorated = false;

            add_css_class ("dock-window");
            DOCK_HEIGHT = app.config.icon_size + 12;

            LayerShellHelper.setup_dock_floating (this, 8, LayerShellHelper.parse_layer (app.config.layer));
            if (monitor != null) {
                GtkLayerShell.set_monitor (this, monitor);
            }
            apply_mode ();

            build_ui ();
            populate_icons ();

            app.config.notify["icon-size"].connect (() => {
                rebuild_dock ();
            });

            var motion = new Gtk.EventControllerMotion ();
            motion.leave.connect (() => {
                cursor_inside = false;
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
            ((Gtk.Widget) this).add_controller (motion);
        }

        public void set_trigger (DockTrigger trigger) {
            this.linked_trigger = trigger;
        }

        public void apply_mode () {
            GtkLayerShell.set_layer (this, LayerShellHelper.parse_layer (app.config.layer));
            LayerShellHelper.apply_dock_mode (this, app.config.dock_mode, DOCK_HEIGHT);
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
                    var pid = shown_classes[j].replace (".desktop", "");
                    if (running.app_class == pid ||
                        running.app_class.down () == pid.down ()) {
                        already_shown = true;
                        break;
                    }
                    var parts = pid.split (".");
                    if (parts.length > 0 &&
                        running.app_class.down () == parts[parts.length - 1].down ()) {
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
                        var icon = new DockIcon (entry, app.config.icon_size, false);
                        icon.set_running (true);
                        icon.set_focused (tracker.focused_class == running.app_class);
                        icon.pin_requested.connect ((id) => {
                            pin_app (id);
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
            main_box.halign = Gtk.Align.CENTER;
            main_box.valign = Gtk.Align.CENTER;

            // Grid button — same structure as DockIcon
            var grid_wrapper = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            grid_wrapper.halign = Gtk.Align.CENTER;

            grid_button = new Gtk.Button ();
            grid_button.add_css_class ("dock-icon");
            grid_button.add_css_class ("flat");
            var grid_image = new Gtk.Image.from_icon_name ("view-app-grid-symbolic");
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

            // Running (not pinned) icons
            running_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            running_box.visible = false;

            main_box.append (grid_wrapper);
            main_box.append (icon_box);
            main_box.append (running_box);

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

            set_child (main_box);

            setup_dock_context_menu (main_box);
        }

        private void setup_dock_context_menu (Gtk.Widget target) {
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_SECONDARY;
            gesture.pressed.connect ((n, x, y) => {
                show_dock_menu ();
            });
            target.add_controller (gesture);
        }

        private void show_dock_menu () {
            var popover = new Gtk.Popover ();
            popover.set_parent (this);
            popover.has_arrow = true;
            popover.autohide = true;

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

            var grid_img = (Gtk.Image) grid_button.get_child ();
            if (grid_img != null) {
                grid_img.pixel_size = app.config.icon_size;
            }
            populate_icons ();
            update_indicators ();
            apply_mode ();
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
                    var icon = new DockIcon (entry, app.config.icon_size);
                    icon.unpin_requested.connect ((id) => {
                        unpin_app (id);
                    });
                    icon.popover_state_changed.connect ((open) => {
                        popover_open = open;
                        if (open) cancel_hide ();
                        else if (autohide_enabled) schedule_hide ();
                    });
                    icon.drag_state_changed.connect ((active) => {
                        dnd_active = active;
                        if (active) {
                            begin_icon_drag (icon);
                        } else {
                            end_icon_drag ();
                        }
                    });
                    icon_box.append (icon);
                }
            }
        }

        // ── DnD gap management ──────────────────────────────────

        private int get_spacer_width () {
            return app.config.icon_size + 8;
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
            gap_spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            gap_spacer.set_size_request (w, 1);
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
                if (gap_spacer_old.get_parent () != null)
                    icon_box.remove (gap_spacer_old);
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
                    if (old_sp.get_parent () != null) {
                        icon_box.remove (old_sp);
                    }
                    if (gap_spacer_old == old_sp) gap_spacer_old = null;
                });
                gap_shrink_anim.play ();
            }

            // Create new spacer at the target position — will grow
            drop_gap_index = new_index;
            gap_spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            gap_spacer.set_size_request (0, 1);
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

        // Remove all spacer widgets and cancel animations.
        private void remove_all_spacers () {
            if (gap_grow_anim != null) { gap_grow_anim.pause (); gap_grow_anim = null; }
            if (gap_shrink_anim != null) { gap_shrink_anim.pause (); gap_shrink_anim = null; }
            if (gap_spacer != null) {
                if (gap_spacer.get_parent () != null)
                    icon_box.remove (gap_spacer);
                gap_spacer = null;
            }
            if (gap_spacer_old != null) {
                if (gap_spacer_old.get_parent () != null)
                    icon_box.remove (gap_spacer_old);
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
