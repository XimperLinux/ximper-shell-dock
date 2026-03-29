namespace XimperShellDock {

    public class DockIcon : Gtk.Box {

        public AppEntry app_entry { get; private set; }
        public string desktop_id { get; private set; }

        private Gtk.Image image;
        private Gtk.Box indicator_box;
        private Gtk.Button button;
        private bool _is_running = false;
        private bool _is_focused = false;

        private static Gtk.Popover? active_popover = null;

        public bool is_pinned { get; private set; }

        public signal void unpin_requested (string desktop_id);
        public signal void pin_requested (string desktop_id);
        public signal void focus_requested (string desktop_id);
        public signal void popover_state_changed (bool open);
        public signal void drag_state_changed (bool active);

        public DockIcon (AppEntry entry, int icon_size, bool pinned = true) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.app_entry = entry;
            this.desktop_id = entry.desktop_id;
            this.is_pinned = pinned;

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
                    focus_requested (desktop_id);
                } else {
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
        }

        public void set_running (bool running) {
            if (_is_running == running) return;
            _is_running = running;
            indicator_box.visible = running;
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

        private void kill_app () {
            // Use hyprctl to close windows of this app
            try {
                Process.spawn_command_line_async (
                    "hyprctl dispatch closewindow address:" + get_window_address ()
                );
            } catch (Error e) {
                // Fallback: kill by class
                try {
                    var app_id = desktop_id.replace (".desktop", "");
                    var parts = app_id.split (".");
                    var class_name = parts.length > 0 ? parts[parts.length - 1] : app_id;
                    Process.spawn_command_line_async (
                        "hyprctl --batch \"dispatch closewindow " + class_name + "\""
                    );
                } catch (Error e2) {}
            }
        }

        private string get_window_address () {
            // Find window address from hyprctl clients
            try {
                string stdout_buf;
                int exit_status;
                Process.spawn_command_line_sync ("hyprctl clients -j", out stdout_buf, null, out exit_status);
                if (exit_status == 0 && stdout_buf != null) {
                    var parser = new Json.Parser ();
                    parser.load_from_data (stdout_buf);
                    var arr = parser.get_root ().get_array ();
                    var app_id = desktop_id.replace (".desktop", "");
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var obj = arr.get_object_element (i);
                        var wclass = obj.get_string_member ("class");
                        if (wclass == app_id || wclass.down () == app_id.down ()) {
                            return obj.get_string_member ("address");
                        }
                        var parts = app_id.split (".");
                        if (parts.length > 0 && wclass.down () == parts[parts.length - 1].down ()) {
                            return obj.get_string_member ("address");
                        }
                    }
                }
            } catch (Error e) {}
            return "";
        }

        public void update_icon_size (int size) {
            image.pixel_size = size;
        }

        private void setup_dnd () {
            var source = new Gtk.DragSource ();
            source.set_actions (Gdk.DragAction.MOVE);
            Gdk.Paintable? drag_paintable = null;
            int drag_w = 0;
            int drag_h = 0;
            source.prepare.connect ((x, y) => {
                // Snapshot the icon before it gets hidden
                var snapshot = new Gtk.Snapshot ();
                this.snapshot (snapshot);
                drag_paintable = snapshot.free_to_paintable (null);
                drag_w = get_width ();
                drag_h = get_height ();
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
                var btn = make_menu_item ("Unpin");
                btn.clicked.connect (() => {
                    popover.popdown ();
                    unpin_requested (desktop_id);
                });
                menu_box.append (btn);
            } else {
                var btn = make_menu_item ("Pin to Dock");
                btn.clicked.connect (() => {
                    popover.popdown ();
                    pin_requested (desktop_id);
                });
                menu_box.append (btn);
            }

            // Quit — only if running
            if (_is_running) {
                menu_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                var btn = make_menu_item ("Quit");
                btn.clicked.connect (() => {
                    popover.popdown ();
                    kill_app ();
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
