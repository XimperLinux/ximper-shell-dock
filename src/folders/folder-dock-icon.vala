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
        private DockPosition dock_position = DockPosition.BOTTOM;
        private Gtk.Box indicator_space;
        private static Gtk.Popover? active_popover = null;

        public signal void remove_requested (string folder_path);
        public signal void settings_requested (string folder_path);
        public signal void popover_state_changed (bool open);
        public signal void stack_requested (FolderDockIcon folder);
        public signal void drag_state_changed (bool active);
        public signal void favorites_changed ();

        public FolderDockIcon (DockFolderConfig folder_config, int icon_size,
                               DockPosition position = DockPosition.BOTTOM) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.folder_config = folder_config;
            this.icon_size = icon_size;
            this.dock_position = position;
            halign = Gtk.Align.CENTER;

            button = new Gtk.Button ();
            button.focusable = false;
            button.add_css_class ("dock-icon");
            button.add_css_class ("flat");

            image = new Gtk.Image.from_icon_name ("folder-open");
            update_folder_presentation ();
            button.tooltip_text = Path.get_basename (folder_path);
            button.clicked.connect (() => { stack_requested (this); });
            append (button);

            indicator_space = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            indicator_space.add_css_class ("dock-indicator-box");
            append (indicator_space);

            setup_context_menu ();
            setup_dnd ();
            apply_position (position);
        }

        public void apply_position (DockPosition position) {
            dock_position = position;
            orientation = position.is_vertical () ? Gtk.Orientation.HORIZONTAL
                                                   : Gtk.Orientation.VERTICAL;
            indicator_space.orientation = position.is_vertical () ? Gtk.Orientation.VERTICAL
                                                                   : Gtk.Orientation.HORIZONTAL;
            if (position == DockPosition.LEFT) reorder_child_after (indicator_space, null);
            else reorder_child_after (indicator_space, button);
            queue_draw ();
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
            double visual_x = !dock_position.is_vertical ()
                ? horizontal_offset + width * (1.0 - magnification) / 2.0
                : (dock_position == DockPosition.LEFT ? 0.0 : width * (1.0 - magnification));
            double visual_y = !dock_position.is_vertical ()
                ? (dock_position == DockPosition.TOP ? 0.0 : height * (1.0 - magnification))
                : horizontal_offset + height * (1.0 - magnification) / 2.0;
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
            if (!dock_position.is_vertical ())
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
            popover.position = dock_position.inward_popover_position ();
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

        public Gtk.Widget create_stack_content (FolderStackWindow stack_window,
                                                int max_width, int max_height) {
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
            title.ellipsize = Pango.EllipsizeMode.END;
            title.margin_start = 6;
            header.append (title);
            var open_header = new Gtk.Button.from_icon_name ("folder-open-symbolic");
            open_header.add_css_class ("flat");
            open_header.tooltip_text = _("Open in Files");
            open_header.clicked.connect (() => {
                stack_window.close_stack ();
                open_in_file_manager ();
            });
            header.append (open_header);
            var close_header = new Gtk.Button.from_icon_name ("window-close-symbolic");
            close_header.add_css_class ("flat");
            close_header.tooltip_text = _("Close Stack");
            close_header.clicked.connect (() => { stack_window.close_stack (); });
            header.append (close_header);
            box.append (header);

            if (folder_config.view_type == "list") {
                append_scrollable_contents (box, create_folder_list_view (stack_window),
                                            max_width, max_height);
            } else {
                var flow = new Gtk.FlowBox ();
                flow.selection_mode = Gtk.SelectionMode.NONE;
                flow.max_children_per_line = folder_config.grid_columns;
                flow.min_children_per_line = folder_config.grid_columns;
                flow.homogeneous = true;
                flow.add_css_class ("dock-folder-grid");
                populate_folder_contents (flow, false, stack_window);
                append_scrollable_contents (box, flow, max_width, max_height);
            }

            return box;
        }

        public int get_stack_width () {
            if (folder_config.view_type == "list")
                return int.max (420, folder_config.item_size + 300);
            return folder_config.grid_columns * int.max (folder_config.item_size + 32, 124) + 40;
        }

        public int get_stack_height () {
            if (folder_config.view_type == "list")
                return int.min (folder_config.grid_rows * (folder_config.item_size + 18) + 88, 720);
            return int.min (folder_config.grid_rows * (folder_config.item_size + 56) + 88, 720);
        }

        private Gtk.ListView create_folder_list_view (FolderStackWindow stack_window) {
            var store = new GLib.ListStore (typeof (FolderListItem));
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
                FolderFileUtils.sort_entries (entries, folder_config.sort_type);
                append_list_favorites (store, folder, entries);
                for (uint i = 0; i < entries.length; i++) {
                    var file = folder.get_child (entries[i].get_name ());
                    if (!is_favorite (file.get_uri ()))
                        store.append (new FolderListItem (file, entries[i]));
                }
            } catch (Error e) {
                warning ("Cannot list folder %s: %s", folder_path, e.message);
            }

            var factory = new Gtk.SignalListItemFactory ();
            factory.bind.connect ((object) => {
                var list_item = object as Gtk.ListItem;
                var entry = list_item.get_item () as FolderListItem;
                if (entry == null) return;
                var button = make_file_button (entry.file, entry.info, true, stack_window);
                setup_file_drag (button, entry.file);
                list_item.set_child (button);
            });
            factory.unbind.connect ((object) => {
                var list_item = object as Gtk.ListItem;
                if (list_item != null) list_item.set_child (null);
            });

            var view = new Gtk.ListView (new Gtk.NoSelection (store), factory);
            view.show_separators = true;
            view.single_click_activate = false;
            view.add_css_class ("dock-folder-list");
            return view;
        }

        private void append_list_favorites (GLib.ListStore store, File folder,
                                            GenericArray<FileInfo> entries) {
            for (uint favorite = 0; favorite < folder_config.favorite_uris.length; favorite++) {
                var uri = folder_config.favorite_uris[favorite];
                for (uint i = 0; i < entries.length; i++) {
                    var file = folder.get_child (entries[i].get_name ());
                    if (file.get_uri () == uri) {
                        store.append (new FolderListItem (file, entries[i]));
                        break;
                    }
                }
            }
        }

        private void populate_folder_contents (Gtk.Widget container, bool list,
                                               FolderStackWindow stack_window) {
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
                FolderFileUtils.sort_entries (entries, folder_config.sort_type);
                // Favourites are shown first, in the explicit order selected
                // by the user. They are not duplicated in the normal list.
                for (uint favorite = 0; favorite < folder_config.favorite_uris.length; favorite++) {
                    var uri = folder_config.favorite_uris[favorite];
                    for (uint i = 0; i < entries.length; i++) {
                        var child = folder.get_child (entries[i].get_name ());
                        if (child.get_uri () == uri) {
                            append_folder_child (container,
                                make_file_button (child, entries[i], list, stack_window), child);
                            break;
                        }
                    }
                }
                for (uint i = 0; i < entries.length; i++) {
                    var child = folder.get_child (entries[i].get_name ());
                    if (is_favorite (child.get_uri ())) continue;
                    append_folder_child (container,
                        make_file_button (child, entries[i], list, stack_window), child);
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

        private void append_scrollable_contents (Gtk.Box box, Gtk.Widget contents,
                                                 int max_width, int max_height) {
            // Keep the layer-shell surface within its monitor. Extra folder
            // items scroll instead of extending the grid beyond the screen.
            var scroll = new Gtk.ScrolledWindow ();
            int viewport_width = 320;
            int viewport_height = 380;
            if (contents is Gtk.FlowBox) {
                int cell_width = int.max (folder_config.item_size + 32, 124);
                int cell_height = folder_config.item_size + 56;
                viewport_width = folder_config.grid_columns * cell_width + 20;
                viewport_height = folder_config.grid_rows * cell_height + 20;
            }
            // Account for the stack's margins, header and spacing.
            int constrained_width = int.min (viewport_width, int.max (max_width - 40, 1));
            int constrained_height = int.min (viewport_height, int.max (max_height - 88, 1));
            scroll.hscrollbar_policy = constrained_width < viewport_width
                ? Gtk.PolicyType.AUTOMATIC : Gtk.PolicyType.NEVER;
            scroll.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            scroll.set_size_request (constrained_width, constrained_height);
            scroll.max_content_width = constrained_width;
            scroll.max_content_height = constrained_height;
            scroll.min_content_width = constrained_width;
            scroll.min_content_height = int.min (constrained_height, 160);
            scroll.propagate_natural_width = false;
            scroll.propagate_natural_height = false;
            scroll.set_child (contents);
            box.append (scroll);
        }

        private Gtk.Widget make_file_button (File file, FileInfo info, bool list,
                                             FolderStackWindow stack_window) {
            var button = new Gtk.Button ();
            button.add_css_class ("flat");
            button.add_css_class ("dock-folder-item");
            if (list) button.add_css_class ("dock-folder-list-item");
            button.tooltip_text = info.get_display_name ();
            var box = new Gtk.Box (list ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL,
                                   list ? 10 : 3);
            int preview_size = folder_config.item_size;
            var content_type = info.get_content_type () ?? "";
            Gtk.Widget visual;
            if (content_type.has_prefix ("image/")) {
                visual = make_preview_widget (file, info, preview_size);
            } else {
                visual = make_file_icon_widget (
                    info.get_icon (), preview_size
                );
            }
            if (list) {
                // Thumbnails preserve their aspect ratio and therefore have
                // a wider natural size than themed MIME icons. A fixed slot
                // keeps every list row aligned while the icon stays legible.
                var visual_slot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                visual_slot.set_size_request (int.max (preview_size, 88), preview_size);
                visual_slot.halign = Gtk.Align.START;
                visual.halign = Gtk.Align.CENTER;
                visual.valign = Gtk.Align.CENTER;
                visual_slot.append (visual);
                box.append (visual_slot);
            } else {
                box.append (visual);
            }
            var label = new Gtk.Label (info.get_display_name ());
            label.width_chars = list ? 20 : 13;
            label.max_width_chars = list ? 36 : 13;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.hexpand = list;
            label.halign = Gtk.Align.START;
            if (!list) {
                label.wrap = true;
                label.wrap_mode = Pango.WrapMode.WORD_CHAR;
                label.lines = 2;
                label.justify = Gtk.Justification.CENTER;
                label.halign = Gtk.Align.CENTER;
            }
            box.append (label);
            button.set_child (box);
            button.clicked.connect (() => {
                FolderFileUtils.open_file (file, info);
            });
            if (!list) {
                button.set_size_request (int.max (folder_config.item_size + 28, 120),
                                         folder_config.item_size + 52);
            }
            if (is_favorite (file.get_uri ()))
                button.add_css_class ("dock-folder-favorite");
            setup_file_context_menu (button, file, stack_window);
            return button;
        }

        private bool is_favorite (string uri) {
            for (uint i = 0; i < folder_config.favorite_uris.length; i++) {
                if (folder_config.favorite_uris[i] == uri) return true;
            }
            return false;
        }

        private void setup_file_context_menu (Gtk.Button button, File file,
                                              FolderStackWindow stack_window) {
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_SECONDARY;
            gesture.pressed.connect ((n_press, x, y) => {
                var popover = new Gtk.Popover ();
                popover.set_parent (button);
                popover.has_arrow = true;
                popover.autohide = true;
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                var favorite = new Gtk.Button.with_label (
                    is_favorite (file.get_uri ()) ? _("Remove from Favorites") : _("Add to Favorites")
                );
                favorite.add_css_class ("flat");
                favorite.halign = Gtk.Align.FILL;
                favorite.clicked.connect (() => {
                    popover.popdown ();
                    // Rebuilding the stack while this popover is still
                    // parented would invalidate its button. Run it after
                    // GTK has completed popover teardown.
                    Idle.add (() => {
                        toggle_favorite (file.get_uri ());
                        return Source.REMOVE;
                    });
                });
                box.append (favorite);
                popover.set_child (box);
                popover.closed.connect (() => {
                    stack_window.set_embedded_popover_open (false);
                    popover.unparent ();
                });
                stack_window.set_embedded_popover_open (true);
                popover.popup ();
            });
            button.add_controller (gesture);
        }

        private void toggle_favorite (string uri) {
            var result = new GenericArray<string> ();
            bool found = false;
            for (uint i = 0; i < folder_config.favorite_uris.length; i++) {
                if (folder_config.favorite_uris[i] == uri) {
                    found = true;
                } else {
                    result.add (folder_config.favorite_uris[i]);
                }
            }
            if (!found) result.add (uri);
            folder_config.favorite_uris = result;
            favorites_changed ();
        }

        // Match the established DockIcon DnD contract first: an ordinary
        // string source with MOVE action. This is the format accepted by the
        // existing chat target and guarantees the drag itself is negotiable.
        private void setup_file_drag (Gtk.Widget source_widget, File file) {
            var source = new Gtk.DragSource ();
            source.set_actions (Gdk.DragAction.MOVE);
            source.set_content (new Gdk.ContentProvider.for_value (file.get_uri ()));
            source.drag_begin.connect ((drag) => {
                var snapshot = new Gtk.Snapshot ();
                source_widget.snapshot (snapshot);
                var paintable = snapshot.free_to_paintable (null);
                source.set_icon (paintable, source_widget.get_width () / 2,
                                 source_widget.get_height () / 2);
            });
            source.drag_cancel.connect ((drag, reason) => {
                return false;
            });
            source.drag_end.connect ((drag, delete_data) => {
            });
            source_widget.add_controller (source);
        }

        private Gtk.Widget make_preview_widget (File file, FileInfo info, int size) {
            var thumbnail = FolderFileUtils.get_cached_thumbnail (file);
            if (thumbnail != null) {
                var picture = new Gtk.Picture.for_file (thumbnail);
                picture.set_size_request (size, size);
                picture.can_shrink = true;
                picture.add_css_class ("dock-folder-thumbnail");
                return picture;
            }
            // Image files without a cached thumbnail must use the exact same
            // sized icon path as non-image files. Otherwise they fall back to
            // Gtk.Image's tiny theme size regardless of the list setting.
            return make_file_icon_widget (info.get_icon (), size);
        }

        private Gtk.Widget make_file_icon_widget (Icon icon, int size) {
            var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
            var paintable = theme.lookup_by_gicon (
                icon, size, get_scale_factor (), get_direction (), Gtk.IconLookupFlags.PRELOAD
            );
            var picture = new Gtk.Picture.for_paintable (paintable);
            picture.set_size_request (size, size);
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            picture.can_shrink = true;
            return picture;
        }

        private void open_in_file_manager () {
            FolderFileUtils.open_in_file_manager (folder_path);
        }
    }
}
