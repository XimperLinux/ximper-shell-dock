namespace XimperShellDock {

    public class FolderDockIcon : Gtk.Box {

        private const int MAX_STACK_ITEMS = 256;

        public DockFolderConfig folder_config { get; private set; }
        public string folder_path { get { return folder_config.path; } }

        private Gtk.Button button;
        private Gtk.Image image;
        private int icon_size;
        private double magnification = 1.0;
        private double horizontal_offset = 0.0;
        private static Gtk.Popover? active_popover = null;
        private uint stack_hide_timeout_id = 0;
        private bool stack_drag_active = false;

        public signal void remove_requested (string folder_path);
        public signal void settings_requested (string folder_path);
        public signal void popover_state_changed (bool open);
        public signal void drag_state_changed (bool active);

        public FolderDockIcon (DockFolderConfig folder_config, int icon_size) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.folder_config = folder_config;
            this.icon_size = icon_size;
            halign = Gtk.Align.CENTER;

            button = new Gtk.Button ();
            button.focusable = false;
            button.add_css_class ("dock-icon");
            button.add_css_class ("flat");

            image = new Gtk.Image.from_icon_name ("folder-open");
            update_folder_presentation ();
            button.tooltip_text = Path.get_basename (folder_path);
            button.clicked.connect (() => { open_folder_popover (); });
            append (button);

            var indicator_space = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            indicator_space.add_css_class ("dock-indicator-box");
            append (indicator_space);

            setup_context_menu ();
            setup_dnd ();
        }

        public void update_icon_size (int size) {
            icon_size = size;
            update_folder_presentation ();
        }

        public void activate_button () {
            button.activate ();
        }

        public Gdk.Paintable? create_drag_paintable (out int hotspot_x, out int hotspot_y) {
            int width = get_width ();
            int height = get_height ();
            double visual_x = horizontal_offset + width * (1.0 - magnification) / 2.0;
            double visual_y = height * (1.0 - magnification);
            int left = (int) (double.max (-visual_x, 0.0) + 0.999);
            int right = (int) (double.max (visual_x + width * magnification - width, 0.0) + 0.999);
            int top = (int) (double.max (-visual_y, 0.0) + 0.999);
            int bottom = (int) (double.max (visual_y + height * magnification - height, 0.0) + 0.999);

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

        private void setup_dnd () {
            var source = new Gtk.DragSource ();
            source.set_actions (Gdk.DragAction.MOVE);
            Gdk.Paintable? drag_paintable = null;
            int hotspot_x = 0;
            int hotspot_y = 0;
            source.prepare.connect ((x, y) => {
                drag_paintable = create_drag_paintable (out hotspot_x, out hotspot_y);
                return new Gdk.ContentProvider.for_value ("folder:" + folder_path);
            });
            source.drag_begin.connect ((drag) => {
                if (drag_paintable != null) source.set_icon (drag_paintable, hotspot_x, hotspot_y);
                drag_state_changed (true);
            });
            source.drag_end.connect ((drag, del) => { drag_state_changed (false); });
            button.add_controller (source);
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
            var open = make_menu_item (_("Open in Files"));
            open.clicked.connect (() => {
                popover.popdown ();
                open_in_file_manager ();
            });
            box.append (open);
            var settings = make_menu_item (_("Stack Settings…"));
            settings.clicked.connect (() => {
                popover.popdown ();
                settings_requested (folder_path);
            });
            box.append (settings);
            var remove = make_menu_item (_("Remove from Dock"));
            remove.clicked.connect (() => {
                popover.popdown ();
                remove_requested (folder_path);
            });
            box.append (remove);
            popover.set_child (box);
            popover.closed.connect (() => {
                popover_state_changed (false);
                if (active_popover == popover) active_popover = null;
                popover.unparent ();
            });
            popover_state_changed (true);
            active_popover = popover;
            popover.popup ();
        }

        private void update_folder_presentation () {
            image = new Gtk.Image.from_icon_name (
                folder_config.display_type == "stack" ? "folder-open" : "folder"
            );
            image.pixel_size = icon_size;
            if (folder_config.display_type != "stack") {
                button.set_child (image);
                return;
            }

            var overlay = new Gtk.Overlay ();
            overlay.set_child (image);
            var preview = new Gtk.Grid ();
            preview.row_spacing = 1;
            preview.column_spacing = 1;
            preview.add_css_class ("dock-stack-preview");
            preview.halign = Gtk.Align.CENTER;
            preview.valign = Gtk.Align.CENTER;
            append_preview_icons (preview);
            overlay.add_overlay (preview);
            button.set_child (overlay);
        }

        private void append_preview_icons (Gtk.Grid preview) {
            var folder = File.new_for_path (folder_path);
            try {
                var enumerator = folder.enumerate_children (
                    "standard::name,standard::icon,standard::content-type",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );
                var image_files = new GenericArray<File> ();
                var image_infos = new GenericArray<FileInfo> ();
                var other_files = new GenericArray<File> ();
                var other_infos = new GenericArray<FileInfo> ();
                while (image_files.length + other_files.length < 32) {
                    var info = enumerator.next_file ();
                    if (info == null) break;
                    var child = folder.get_child (info.get_name ());
                    var content_type = info.get_content_type () ?? "";
                    if (content_type.has_prefix ("image/")) {
                        image_files.add (child);
                        image_infos.add (info);
                    } else {
                        other_files.add (child);
                        other_infos.add (info);
                    }
                }
                enumerator.close ();

                int position = 0;
                for (uint i = 0; i < image_files.length && position < 4; i++) {
                    preview.attach (
                        make_preview_widget (image_files[i], image_infos[i],
                                             int.max (12, icon_size / 2)),
                        position % 2, position / 2, 1, 1
                    );
                    position++;
                }
                for (uint i = 0; i < other_files.length && position < 4; i++) {
                    var icon = new Gtk.Image ();
                    icon.gicon = other_infos[i].get_icon ();
                    icon.pixel_size = int.max (12, icon_size / 2);
                    preview.attach (icon, position % 2, position / 2, 1, 1);
                    position++;
                }
            } catch (Error e) {
                // Keep the folder base icon when its contents are unavailable.
            }
        }

        private void open_folder_popover () {
            if (active_popover != null) active_popover.popdown ();
            var popover = new Gtk.Popover ();
            popover.set_parent (button);
            popover.has_arrow = true;
            // A Stack is a file browser, not a menu. An autohiding popover
            // owns a Wayland input grab, which prevents its drag source from
            // negotiating with windows outside the dock.
            popover.autohide = false;
            popover.position = Gtk.PositionType.TOP;
            popover.add_css_class ("dock-folder-popover");

            // The Stack cannot use Gtk.Popover autohide: that takes a Wayland
            // input grab and blocks DnD to other applications. Recreate the
            // expected behaviour locally, while keeping the surface free for
            // external drag targets.
            var stack_motion = new Gtk.EventControllerMotion ();
            stack_motion.enter.connect ((x, y) => { cancel_stack_hide (); });
            stack_motion.leave.connect (() => { schedule_stack_hide (popover); });
            ((Gtk.Widget) popover).add_controller (stack_motion);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            box.add_css_class ("dock-folder-view");
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 10;
            box.margin_end = 10;
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var title = new Gtk.Label (Path.get_basename (folder_path));
            title.add_css_class ("heading");
            title.add_css_class ("title-1");
            title.halign = Gtk.Align.START;
            title.hexpand = true;
            title.margin_start = 6;
            header.append (title);
            var open_header = new Gtk.Button.from_icon_name ("folder-open-symbolic");
            open_header.add_css_class ("flat");
            open_header.tooltip_text = _("Open in Files");
            open_header.clicked.connect (() => {
                popover.popdown ();
                open_in_file_manager ();
            });
            header.append (open_header);
            var close_header = new Gtk.Button.from_icon_name ("window-close-symbolic");
            close_header.add_css_class ("flat");
            close_header.tooltip_text = _("Close Stack");
            close_header.clicked.connect (() => { popover.popdown (); });
            header.append (close_header);
            box.append (header);

            if (folder_config.view_type == "list") {
                var list = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                populate_folder_contents (list, true);
                append_scrollable_contents (box, list);
            } else {
                var flow = new Gtk.FlowBox ();
                flow.selection_mode = Gtk.SelectionMode.NONE;
                flow.max_children_per_line = folder_config.view_type == "fan" ? 7 : 4;
                flow.min_children_per_line = folder_config.view_type == "fan" ? 5 : 4;
                flow.homogeneous = true;
                flow.add_css_class ("dock-folder-grid");
                if (folder_config.view_type == "fan") flow.add_css_class ("dock-folder-fan");
                populate_folder_contents (flow, false);
                append_scrollable_contents (box, flow);
            }

            popover.set_child (box);
            popover.closed.connect (() => {
                cancel_stack_hide ();
                popover_state_changed (false);
                if (active_popover == popover) active_popover = null;
                popover.unparent ();
            });
            popover_state_changed (true);
            active_popover = popover;
            popover.popup ();
        }

        private void populate_folder_contents (Gtk.Widget container, bool list) {
            var folder = File.new_for_path (folder_path);
            try {
                var enumerator = folder.enumerate_children (
                    "standard::name,standard::display-name,standard::icon,standard::content-type,time::modified",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );
                var entries = new GenericArray<FileInfo> ();
                while (entries.length < MAX_STACK_ITEMS) {
                    var info = enumerator.next_file ();
                    if (info == null) break;
                    entries.add (info);
                }
                enumerator.close ();
                sort_folder_entries (entries);
                for (uint i = 0; i < entries.length; i++) {
                    var child = folder.get_child (entries[i].get_name ());
                    append_folder_child (container,
                        make_file_button (child, entries[i], list), child);
                }
                if (entries.length == 0) {
                    var empty = new Gtk.Label (_("Folder is empty"));
                    empty.add_css_class ("dim-label");
                    append_folder_child (container, empty);
                }
            } catch (Error e) {
                var unavailable = new Gtk.Label (_("Folder is unavailable"));
                unavailable.add_css_class ("dim-label");
                append_folder_child (container, unavailable);
            }
        }

        private void append_folder_child (Gtk.Widget container, Gtk.Widget child,
                                          File? drag_file = null) {
            if (container is Gtk.FlowBox) {
                // Gtk.FlowBox creates the FlowBoxChild itself. The actual
                // interactive widget is the button, just like DockIcon.
                if (drag_file != null) setup_file_drag (child, drag_file);
                ((Gtk.FlowBox) container).append (child);
            } else {
                if (drag_file != null) setup_file_drag (child, drag_file);
                ((Gtk.Box) container).append (child);
            }
        }

        private void append_scrollable_contents (Gtk.Box box, Gtk.Widget contents) {
            // A Stack must never grow the layer-shell surface or leave the
            // monitor. Extra items scroll within this fixed visual envelope.
            var scroll = new Gtk.ScrolledWindow ();
            int viewport_width = 320;
            if (contents is Gtk.FlowBox) viewport_width = 360;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroll.set_size_request (viewport_width, 380);
            scroll.max_content_width = viewport_width;
            scroll.max_content_height = 380;
            scroll.min_content_width = viewport_width;
            scroll.min_content_height = 160;
            scroll.propagate_natural_width = false;
            scroll.propagate_natural_height = false;
            scroll.set_child (contents);
            box.append (scroll);
        }

        private void sort_folder_entries (GenericArray<FileInfo> entries) {
            for (uint i = 0; i < entries.length; i++) {
                for (uint j = i + 1; j < entries.length; j++) {
                    if (compare_file_info (entries[i], entries[j]) > 0) {
                        var item = entries[i];
                        entries[i] = entries[j];
                        entries[j] = item;
                    }
                }
            }
        }

        private int compare_file_info (FileInfo a, FileInfo b) {
            if (folder_config.sort_type == "kind")
                return strcmp (a.get_content_type () ?? "", b.get_content_type () ?? "");
            if (folder_config.sort_type == "modified") {
                var a_time = a.get_modification_date_time ();
                var b_time = b.get_modification_date_time ();
                var a_value = a_time != null ? a_time.to_unix () : 0;
                var b_value = b_time != null ? b_time.to_unix () : 0;
                return a_value == b_value ? 0 : (a_value > b_value ? -1 : 1);
            }
            return strcmp (a.get_display_name (), b.get_display_name ());
        }

        private Gtk.Widget make_file_button (File file, FileInfo info, bool list) {
            var button = new Gtk.Button ();
            button.add_css_class ("flat");
            button.add_css_class ("dock-folder-item");
            if (list) button.add_css_class ("dock-folder-list-item");
            button.tooltip_text = info.get_display_name ();
            var box = new Gtk.Box (list ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL, 3);
            int preview_size = list ? 24 : 56;
            var content_type = info.get_content_type () ?? "";
            if (content_type.has_prefix ("image/")) {
                box.append (make_preview_widget (file, info, preview_size));
            } else {
                var file_icon = new Gtk.Image ();
                file_icon.gicon = info.get_icon ();
                file_icon.pixel_size = preview_size;
                box.append (file_icon);
            }
            var label = new Gtk.Label (info.get_display_name ());
            label.width_chars = list ? 20 : 9;
            label.max_width_chars = list ? 28 : 9;
            label.ellipsize = Pango.EllipsizeMode.END;
            box.append (label);
            button.set_child (box);
            button.clicked.connect (() => {
                try {
                    AppInfo.launch_default_for_uri (file.get_uri (), null);
                } catch (Error e) {
                    warning ("Cannot open %s: %s", file.get_uri (), e.message);
                }
            });
            return button;
        }

        // Match the established DockIcon DnD contract first: an ordinary
        // string source with MOVE action. This is the format accepted by the
        // existing chat target and guarantees the drag itself is negotiable.
        private void setup_file_drag (Gtk.Widget source_widget, File file) {
            var source = new Gtk.DragSource ();
            source.set_actions (Gdk.DragAction.MOVE);
            source.set_content (new Gdk.ContentProvider.for_value (file.get_uri ()));
            source.drag_begin.connect ((drag) => {
                stack_drag_active = true;
                cancel_stack_hide ();
                var snapshot = new Gtk.Snapshot ();
                source_widget.snapshot (snapshot);
                var paintable = snapshot.free_to_paintable (null);
                source.set_icon (paintable, source_widget.get_width () / 2,
                                 source_widget.get_height () / 2);
            });
            source.drag_cancel.connect ((drag, reason) => {
                finish_stack_drag ();
                return false;
            });
            source.drag_end.connect ((drag, delete_data) => {
                finish_stack_drag ();
            });
            source_widget.add_controller (source);
        }

        private void schedule_stack_hide (Gtk.Popover popover) {
            cancel_stack_hide ();
            stack_hide_timeout_id = Timeout.add (350, () => {
                stack_hide_timeout_id = 0;
                if (!stack_drag_active) popover.popdown ();
                return Source.REMOVE;
            });
        }

        private void cancel_stack_hide () {
            if (stack_hide_timeout_id == 0) return;
            Source.remove (stack_hide_timeout_id);
            stack_hide_timeout_id = 0;
        }

        private void finish_stack_drag () {
            stack_drag_active = false;
            cancel_stack_hide ();
            if (active_popover != null) active_popover.popdown ();
        }

        private Gtk.Widget make_preview_widget (File file, FileInfo info, int size) {
            var thumbnail = get_cached_thumbnail (file);
            if (thumbnail != null) {
                var picture = new Gtk.Picture.for_file (thumbnail);
                picture.set_size_request (size, size);
                picture.can_shrink = true;
                picture.add_css_class ("dock-folder-thumbnail");
                return picture;
            }
            var icon = new Gtk.Image ();
            icon.gicon = info.get_icon ();
            icon.pixel_size = size;
            return icon;
        }

        private File? get_cached_thumbnail (File file) {
            var uri = file.get_uri ();
            var digest = Checksum.compute_for_string (ChecksumType.MD5, uri);
            var path = Path.build_filename (
                Environment.get_user_cache_dir (), "thumbnails", "normal", digest + ".png"
            );
            return FileUtils.test (path, FileTest.EXISTS) ? File.new_for_path (path) : null;
        }

        private void open_in_file_manager () {
            try {
                AppInfo.launch_default_for_uri (File.new_for_path (folder_path).get_uri (), null);
            } catch (Error e) {
                warning ("Cannot open folder %s: %s", folder_path, e.message);
            }
        }
    }
}
