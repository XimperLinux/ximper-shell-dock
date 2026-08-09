namespace XimperShellDock {

    // A system item, deliberately kept outside ConfigManager.dock_items so it
    // cannot be reordered with, or accidentally removed as, a pinned app.
    public class TrashDockIcon : Gtk.Box {

        private Gtk.Button button;
        private Gtk.Image image;
        private int icon_size;
        private double magnification = 1.0;
        private double horizontal_offset = 0.0;
        private File trash_directory;
        private FileMonitor? trash_monitor;
        private uint icon_refresh_id = 0;
        private static Gtk.Popover? active_popover = null;

        public signal void drag_state_changed (bool active);
        public signal void popover_state_changed (bool open);

        public TrashDockIcon (int icon_size) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.icon_size = icon_size;
            halign = Gtk.Align.CENTER;

            button = new Gtk.Button ();
            button.focusable = false;
            button.add_css_class ("dock-icon");
            button.add_css_class ("flat");
            button.add_css_class ("dock-trash-icon");
            button.tooltip_text = _("Trash");

            image = new Gtk.Image.from_icon_name ("user-trash-symbolic");
            image.pixel_size = icon_size;
            button.set_child (image);
            button.clicked.connect (() => { open_trash (); });
            append (button);

            var indicator_space = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            indicator_space.add_css_class ("dock-indicator-box");
            append (indicator_space);

            setup_file_drop_target ();
            setup_context_menu ();
            setup_trash_monitor ();
            refresh_icon ();

            destroy.connect (() => {
                if (icon_refresh_id != 0) Source.remove (icon_refresh_id);
                if (trash_monitor != null) trash_monitor.cancel ();
            });
        }

        public void update_icon_size (int size) {
            icon_size = size;
            image.pixel_size = size;
        }

        public void activate_button () {
            button.activate ();
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
                if (moved) schedule_icon_refresh ();
                return moved;
            });
            button.add_controller (target);
        }

        private void setup_context_menu () {
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_SECONDARY;
            gesture.pressed.connect ((n, x, y) => { open_context_popover (); });
            button.add_controller (gesture);
        }

        private Gtk.Button make_menu_item (string label) {
            var item = new Gtk.Button.with_label (label);
            item.add_css_class ("flat");
            item.halign = Gtk.Align.FILL;
            return item;
        }

        private void open_context_popover () {
            if (active_popover != null) active_popover.popdown ();

            var popover = new Gtk.Popover ();
            popover.set_parent (button);
            popover.has_arrow = true;
            popover.add_css_class ("menu");
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var empty = make_menu_item (_("Empty Trash…"));
            empty.add_css_class ("destructive-action");
            empty.clicked.connect (() => {
                popover.popdown ();
                open_empty_confirmation ();
            });
            box.append (empty);
            popover.set_child (box);
            popover.closed.connect (() => {
                popover_state_changed (false);
                if (active_popover == popover) active_popover = null;
                popover.unparent ();
            });
            active_popover = popover;
            popover_state_changed (true);
            popover.popup ();
        }

        private void open_empty_confirmation () {
            var popover = new Gtk.Popover ();
            popover.set_parent (button);
            popover.has_arrow = true;
            popover.position = Gtk.PositionType.TOP;
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 10;
            box.margin_end = 10;
            var title = new Gtk.Label (_("Empty Trash?"));
            title.add_css_class ("heading");
            title.halign = Gtk.Align.START;
            box.append (title);
            var warning_label = new Gtk.Label (
                _("All items in Trash will be permanently deleted.")
            );
            warning_label.wrap = true;
            warning_label.max_width_chars = 34;
            warning_label.halign = Gtk.Align.START;
            box.append (warning_label);
            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            actions.halign = Gtk.Align.END;
            var cancel = new Gtk.Button.with_label (_("Cancel"));
            cancel.add_css_class ("flat");
            cancel.clicked.connect (() => { popover.popdown (); });
            actions.append (cancel);
            var confirm = new Gtk.Button.with_label (_("Empty Trash"));
            confirm.add_css_class ("destructive-action");
            confirm.clicked.connect (() => {
                var error_message = empty_trash ();
                if (error_message == null) {
                    schedule_icon_refresh ();
                    popover.popdown ();
                } else {
                    warning_label.label = error_message;
                    warning_label.add_css_class ("error");
                }
            });
            actions.append (confirm);
            box.append (actions);
            popover.set_child (box);
            popover.closed.connect (() => {
                popover_state_changed (false);
                popover.unparent ();
            });
            popover_state_changed (true);
            popover.popup ();
        }

        private string? empty_trash () {
            try {
                string stdout_buf;
                string stderr_buf;
                int exit_status;
                Process.spawn_command_line_sync (
                    "gio trash --empty", out stdout_buf, out stderr_buf, out exit_status
                );
                if (exit_status != 0) {
                    warning ("Failed to empty Trash: %s", stderr_buf);
                    var message = stderr_buf.strip ();
                    return message.length > 0 ? message : _("Could not empty Trash.");
                }
                return null;
            } catch (Error e) {
                warning ("Failed to empty Trash: %s", e.message);
                return e.message;
            }
        }

        private void setup_trash_monitor () {
            trash_directory = File.new_for_uri ("trash:///");
            try {
                trash_monitor = trash_directory.monitor_directory (FileMonitorFlags.NONE, null);
                trash_monitor.changed.connect ((file, other_file, event_type) => {
                    schedule_icon_refresh ();
                });
            } catch (Error e) {
                // The icon remains usable even when a backend does not expose
                // directory monitoring for trash:///.
                warning ("Failed to monitor Trash: %s", e.message);
            }
        }

        private void schedule_icon_refresh () {
            if (icon_refresh_id != 0) return;
            icon_refresh_id = Idle.add (() => {
                icon_refresh_id = 0;
                refresh_icon ();
                return Source.REMOVE;
            });
        }

        private void refresh_icon () {
            string icon_name = trash_has_items ()
                ? "user-trash-full-symbolic"
                : "user-trash-symbolic";
            var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
            image.icon_name = icon_theme.has_icon (icon_name)
                ? icon_name : "user-trash-symbolic";
        }

        private bool trash_has_items () {
            try {
                var enumerator = trash_directory.enumerate_children (
                    "standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );
                var has_items = enumerator.next_file () != null;
                enumerator.close ();
                return has_items;
            } catch (Error e) {
                warning ("Failed to inspect Trash: %s", e.message);
                return false;
            }
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
