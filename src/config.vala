namespace XimperShellDock {

    public class ConfigManager : Object {

        public DockMode dock_mode { get; set; default = DockMode.FLOATING; }
        public DockPosition dock_position { get; set; default = DockPosition.BOTTOM; }
        public bool show_trash { get; set; default = false; }
        public bool magnify_on_hover { get; set; default = false; }
        public bool bounce_on_launch { get; set; default = false; }
        public int bounce_duration { get; set; default = 200; }
        public int magnify_scale { get; set; default = 135; }
        public double magnify_radius { get; set; default = 2.0; }
        public int magnify_animation_duration { get; set; default = 120; }
        public int icon_size { get; set; default = 32; }
        public int hide_delay { get; set; default = 300; }
        public int floating_margin { get; set; default = 8; }
        public string layer { get; set; default = "top"; }
        public string launcher_fallback { get; set; default = "wofi --show drun"; }
        // Empty means every currently connected monitor.  This preserves the
        // behaviour of configuration files written before monitor selection
        // was introduced.
        public GenericArray<string> monitor_ids;
        private bool monitor_selection_explicit = false;
        // Ordered dock contents. App entries are stored as "app:<desktop-id>",
        // folders as "folder:<absolute-path>".
        public GenericArray<string> dock_items;
        public GenericArray<DockFolderConfig> dock_folders;

        private string config_path;
        public string config_file { get { return config_path; } }

        public ConfigManager () {
            monitor_ids = new GenericArray<string> ();
            dock_items = new GenericArray<string> ();
            dock_folders = new GenericArray<DockFolderConfig> ();

            config_path = Path.build_filename (
                Environment.get_user_config_dir (), "ximper-shell", "dock", "config.json"
            );
        }

        public void load () {
            if (!FileUtils.test (config_path, FileTest.EXISTS)) {
                reset_to_defaults ();
                create_default ();
                return;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (config_path);
                var root_node = parser.get_root ();
                if (root_node.get_node_type () != Json.NodeType.OBJECT)
                    throw new IOError.INVALID_DATA ("Dock config root must be an object");
                var root = root_node.get_object ();
                // A malformed JSON file must not wipe the running layout on reload.
                reset_to_defaults ();
                bool config_migrated = false;

                if (root.has_member ("mode"))
                    dock_mode = DockMode.from_string (root.get_string_member ("mode"));
                if (root.has_member ("position"))
                    dock_position = DockPosition.from_string (root.get_string_member ("position"));
                if (root.has_member ("autohide"))
                    config_migrated = true;
                if (root.has_member ("show_trash"))
                    show_trash = root.get_boolean_member ("show_trash");
                if (root.has_member ("magnify_on_hover"))
                    magnify_on_hover = root.get_boolean_member ("magnify_on_hover");
                if (root.has_member ("bounce_on_launch"))
                    bounce_on_launch = root.get_boolean_member ("bounce_on_launch");
                if (root.has_member ("bounce_duration"))
                    bounce_duration = ((int) root.get_int_member ("bounce_duration")).clamp (100, 500);
                if (root.has_member ("magnify_scale"))
                    magnify_scale = (int) root.get_int_member ("magnify_scale");
                if (root.has_member ("magnify_radius"))
                    magnify_radius = root.get_double_member ("magnify_radius");
                if (root.has_member ("magnify_animation_duration"))
                    magnify_animation_duration = (int) root.get_int_member ("magnify_animation_duration");
                if (root.has_member ("icon_size"))
                    icon_size = (int) root.get_int_member ("icon_size");
                if (root.has_member ("hide_delay"))
                    hide_delay = ((int) root.get_int_member ("hide_delay")).clamp (0, 5000);
                if (root.has_member ("floating_margin"))
                    floating_margin = ((int) root.get_int_member ("floating_margin")).clamp (0, 128);
                if (root.has_member ("layer")) {
                    var layer_node = root.get_member ("layer");
                    if (layer_node.get_value_type () == typeof (string))
                        layer = LayerShellHelper.normalize_layer_name (layer_node.get_string ());
                    else {
                        layer = LayerShellHelper.layer_name_from_legacy ((int) layer_node.get_int ());
                        config_migrated = true;
                    }
                }
                if (root.has_member ("launcher_fallback"))
                    launcher_fallback = root.get_string_member ("launcher_fallback");

                if (root.has_member ("monitors")) {
                    monitor_selection_explicit = true;
                    monitor_ids = new GenericArray<string> ();
                    var monitors = root.get_array_member ("monitors");
                    monitors.foreach_element ((array, i, node) => {
                        monitor_ids.add (node.get_string ());
                    });
                }

                if (root.has_member ("dock_items")) {
                    dock_items = new GenericArray<string> ();
                    var arr = root.get_array_member ("dock_items");
                    arr.foreach_element ((array, i, node) => {
                        var item = node.get_string ();
                        if (item.has_prefix ("app:") || item.has_prefix ("folder:"))
                            dock_items.add (item);
                    });
                }
                if (root.has_member ("dock_folders")) {
                    var folders = root.get_array_member ("dock_folders");
                    folders.foreach_element ((array, i, node) => {
                        var folder = node.get_object ();
                        if (!folder.has_member ("path")) return;
                        var config = new DockFolderConfig (
                            folder.get_string_member ("path"),
                            folder.has_member ("display") ? folder.get_string_member ("display") : "stack",
                            folder.has_member ("view") ? folder.get_string_member ("view") : "grid",
                            folder.has_member ("sort") ? folder.get_string_member ("sort") : "name",
                            folder.has_member ("columns") ? (int) folder.get_int_member ("columns") : 4,
                            folder.has_member ("rows") ? (int) folder.get_int_member ("rows") : 3,
                            folder.has_member ("item_size") ? (int) folder.get_int_member ("item_size") : 56
                        );
                        if (folder.has_member ("favorites")) {
                            var favorites = folder.get_array_member ("favorites");
                            favorites.foreach_element ((array, index, item) => {
                                var uri = item.get_string ();
                                if (uri != null && uri.length > 0)
                                    config.favorite_uris.add (uri);
                            });
                        }
                        dock_folders.add (config);
                    });
                }
                migrate_legacy_folder_items ();
                if (config_migrated) save ();
            } catch (Error e) {
                warning ("Failed to load config: %s", e.message);
            }
        }

        private void reset_to_defaults () {
            dock_mode = DockMode.FLOATING;
            dock_position = DockPosition.BOTTOM;
            show_trash = false;
            magnify_on_hover = false;
            bounce_on_launch = false;
            bounce_duration = 200;
            magnify_scale = 135;
            magnify_radius = 2.0;
            magnify_animation_duration = 120;
            icon_size = 32;
            hide_delay = 300;
            floating_margin = 8;
            layer = "top";
            launcher_fallback = "wofi --show drun";
            monitor_ids = new GenericArray<string> ();
            monitor_selection_explicit = false;
            dock_items = new GenericArray<string> ();
            dock_folders = new GenericArray<DockFolderConfig> ();
        }

        public void save () {
            var builder = new Json.Builder ();

            builder.begin_object ();

            builder.set_member_name ("mode");
            builder.add_string_value (dock_mode.to_string ());
            builder.set_member_name ("position");
            builder.add_string_value (dock_position.to_string ());
            builder.set_member_name ("show_trash");
            builder.add_boolean_value (show_trash);
            builder.set_member_name ("magnify_on_hover");
            builder.add_boolean_value (magnify_on_hover);
            builder.set_member_name ("bounce_on_launch");
            builder.add_boolean_value (bounce_on_launch);
            builder.set_member_name ("bounce_duration");
            builder.add_int_value (bounce_duration);
            builder.set_member_name ("magnify_scale");
            builder.add_int_value (magnify_scale);
            builder.set_member_name ("magnify_radius");
            builder.add_double_value (magnify_radius);
            builder.set_member_name ("magnify_animation_duration");
            builder.add_int_value (magnify_animation_duration);
            builder.set_member_name ("icon_size");
            builder.add_int_value (icon_size);
            builder.set_member_name ("hide_delay");
            builder.add_int_value (hide_delay);
            builder.set_member_name ("floating_margin");
            builder.add_int_value (floating_margin);
            builder.set_member_name ("layer");
            builder.add_string_value (LayerShellHelper.normalize_layer_name (layer));
            builder.set_member_name ("launcher_fallback");
            builder.add_string_value (launcher_fallback);
            if (monitor_selection_explicit) {
                builder.set_member_name ("monitors");
                builder.begin_array ();
                for (uint i = 0; i < monitor_ids.length; i++) {
                    builder.add_string_value (monitor_ids[i]);
                }
                builder.end_array ();
            }
            builder.set_member_name ("dock_folders");
            builder.begin_array ();
            for (uint i = 0; i < dock_folders.length; i++) {
                var folder = dock_folders[i];
                builder.begin_object ();
                builder.set_member_name ("path");
                builder.add_string_value (folder.path);
                builder.set_member_name ("display");
                builder.add_string_value (folder.display_type);
                builder.set_member_name ("view");
                builder.add_string_value (folder.view_type);
                builder.set_member_name ("sort");
                builder.add_string_value (folder.sort_type);
                builder.set_member_name ("columns");
                builder.add_int_value (folder.grid_columns);
                builder.set_member_name ("rows");
                builder.add_int_value (folder.grid_rows);
                builder.set_member_name ("item_size");
                builder.add_int_value (folder.item_size);
                builder.set_member_name ("favorites");
                builder.begin_array ();
                for (uint j = 0; j < folder.favorite_uris.length; j++) {
                    builder.add_string_value (folder.favorite_uris[j]);
                }
                builder.end_array ();
                builder.end_object ();
            }
            builder.end_array ();

            builder.set_member_name ("dock_items");
            builder.begin_array ();
            for (uint i = 0; i < dock_items.length; i++) {
                builder.add_string_value (dock_items[i]);
            }
            builder.end_array ();

            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            generator.pretty = true;
            generator.indent = 2;

            try {
                var dir = Path.get_dirname (config_path);
                DirUtils.create_with_parents (dir, 0755);
                generator.to_file (config_path);
            } catch (Error e) {
                warning ("Failed to save config: %s", e.message);
            }
        }

        private void create_default () {
            dock_items.add (app_item ("org.gnome.Nautilus.desktop"));
            dock_items.add (app_item ("org.gnome.TextEditor.desktop"));
            dock_items.add (app_item ("firefox.desktop"));
            save ();
        }

        public static string app_item (string desktop_id) {
            return "app:" + desktop_id;
        }

        public bool is_monitor_enabled (string monitor_id) {
            // An absent setting means "all monitors", which is also the
            // backwards-compatible default for existing users.
            if (monitor_ids.length == 0) return true;
            for (uint i = 0; i < monitor_ids.length; i++) {
                if (monitor_ids[i] == monitor_id) return true;
            }
            return false;
        }

        public void set_monitor_ids (GenericArray<string> ids) {
            monitor_ids = ids;
            monitor_selection_explicit = true;
        }

        public static bool is_app_item (string item) {
            return item.has_prefix ("app:");
        }

        public static bool is_folder_item (string item) {
            return item.has_prefix ("folder:");
        }

        public static string item_desktop_id (string item) {
            return is_app_item (item) ? item.substring (4) : "";
        }

        public static string item_folder_path (string item) {
            return is_folder_item (item) ? item.substring (7) : "";
        }

        public bool has_dock_item (string item) {
            for (uint i = 0; i < dock_items.length; i++) {
                if (dock_items[i] == item) return true;
            }
            return false;
        }

        public void add_dock_item (string item) {
            if (has_dock_item (item)) return;
            dock_items.add (item);
        }

        public void remove_dock_item (string item) {
            var result = new GenericArray<string> ();
            for (uint i = 0; i < dock_items.length; i++) {
                if (dock_items[i] != item) result.add (dock_items[i]);
            }
            dock_items = result;
        }

        public void reorder_dock_item (string item, int position) {
            remove_dock_item (item);
            if (position < 0) position = 0;
            if (position > (int) dock_items.length) position = (int) dock_items.length;
            dock_items.insert (position, item);
        }

        private void migrate_legacy_folder_items () {
            var applications = new GenericArray<string> ();
            for (uint i = 0; i < dock_items.length; i++) {
                if (is_folder_item (dock_items[i])) {
                    add_folder (item_folder_path (dock_items[i]));
                } else {
                    applications.add (dock_items[i]);
                }
            }
            dock_items = applications;
        }

        public DockFolderConfig? find_folder (string path) {
            for (uint i = 0; i < dock_folders.length; i++) {
                if (dock_folders[i].path == path) return dock_folders[i];
            }
            return null;
        }

        public void add_folder (string path) {
            if (find_folder (path) == null)
                dock_folders.add (new DockFolderConfig (path));
        }

        public void add_folder_at (string path, int position) {
            if (find_folder (path) != null) return;
            if (position < 0) position = 0;
            if (position > (int) dock_folders.length) position = (int) dock_folders.length;
            dock_folders.insert (position, new DockFolderConfig (path));
        }

        public void remove_folder (string path) {
            var result = new GenericArray<DockFolderConfig> ();
            for (uint i = 0; i < dock_folders.length; i++) {
                if (dock_folders[i].path != path) result.add (dock_folders[i]);
            }
            dock_folders = result;
        }

        public void reorder_folder (string path, int position) {
            DockFolderConfig? folder = find_folder (path);
            if (folder == null) return;
            remove_folder (path);
            if (position < 0) position = 0;
            if (position > (int) dock_folders.length) position = (int) dock_folders.length;
            dock_folders.insert (position, folder);
        }
    }
}
