namespace XimperShellDock {

    public class DockFolderConfig : Object {
        public string path;
        public string display_type;
        public string view_type;
        public string sort_type;

        public DockFolderConfig (string path, string display_type = "stack",
                                 string view_type = "grid", string sort_type = "name") {
            this.path = path;
            this.display_type = display_type;
            this.view_type = view_type;
            this.sort_type = sort_type;
        }
    }

    public enum DockMode {
        FLOATING,
        PINNED;

        public static DockMode from_string (string val) {
            if (val == "pinned") return PINNED;
            return FLOATING;
        }

        public string to_string () {
            if (this == PINNED) return "pinned";
            return "floating";
        }
    }

    public class ConfigManager : Object {

        public DockMode dock_mode { get; set; default = DockMode.FLOATING; }
        public bool autohide { get; set; default = false; }
        public bool magnify_on_hover { get; set; default = false; }
        public bool bounce_on_launch { get; set; default = false; }
        public int bounce_duration { get; set; default = 200; }
        public int magnify_scale { get; set; default = 135; }
        public double magnify_radius { get; set; default = 2.0; }
        public int magnify_animation_duration { get; set; default = 120; }
        public int icon_size { get; set; default = 48; }
        public int layer { get; set; default = 2; }
        public string launcher_fallback { get; set; default = "wofi --show drun"; }
        public GenericArray<string> pinned_apps;
        // Ordered dock contents. App entries are stored as "app:<desktop-id>",
        // folders as "folder:<absolute-path>".  pinned_apps is retained as a
        // compatibility view for the D-Bus API and older configuration files.
        public GenericArray<string> dock_items;
        public GenericArray<DockFolderConfig> dock_folders;

        private string config_path;

        public ConfigManager () {
            pinned_apps = new GenericArray<string> ();
            dock_items = new GenericArray<string> ();
            dock_folders = new GenericArray<DockFolderConfig> ();

            config_path = Path.build_filename (
                Environment.get_user_config_dir (), "ximper-shell", "dock", "config.json"
            );
        }

        public void load () {
            if (!FileUtils.test (config_path, FileTest.EXISTS)) {
                create_default ();
                return;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (config_path);

                var root = parser.get_root ().get_object ();

                if (root.has_member ("mode"))
                    dock_mode = DockMode.from_string (root.get_string_member ("mode"));
                if (root.has_member ("autohide"))
                    autohide = root.get_boolean_member ("autohide");
                if (root.has_member ("magnify_on_hover"))
                    magnify_on_hover = root.get_boolean_member ("magnify_on_hover");
                if (root.has_member ("bounce_on_launch"))
                    bounce_on_launch = root.get_boolean_member ("bounce_on_launch");
                if (root.has_member ("bounce_duration"))
                    bounce_duration = (int) root.get_int_member ("bounce_duration");
                if (root.has_member ("magnify_scale"))
                    magnify_scale = (int) root.get_int_member ("magnify_scale");
                if (root.has_member ("magnify_radius"))
                    magnify_radius = root.get_double_member ("magnify_radius");
                if (root.has_member ("magnify_animation_duration"))
                    magnify_animation_duration = (int) root.get_int_member ("magnify_animation_duration");
                if (root.has_member ("icon_size"))
                    icon_size = (int) root.get_int_member ("icon_size");
                if (root.has_member ("layer"))
                    layer = (int) root.get_int_member ("layer");
                if (root.has_member ("launcher_fallback"))
                    launcher_fallback = root.get_string_member ("launcher_fallback");

                if (root.has_member ("pinned_apps")) {
                    pinned_apps = new GenericArray<string> ();
                    var arr = root.get_array_member ("pinned_apps");
                    arr.foreach_element ((array, i, node) => {
                        pinned_apps.add (node.get_string ());
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
                } else {
                    migrate_pinned_apps ();
                }
                if (root.has_member ("dock_folders")) {
                    var folders = root.get_array_member ("dock_folders");
                    folders.foreach_element ((array, i, node) => {
                        var folder = node.get_object ();
                        if (!folder.has_member ("path")) return;
                        dock_folders.add (new DockFolderConfig (
                            folder.get_string_member ("path"),
                            folder.has_member ("display") ? folder.get_string_member ("display") : "stack",
                            folder.has_member ("view") ? folder.get_string_member ("view") : "grid",
                            folder.has_member ("sort") ? folder.get_string_member ("sort") : "name"
                        ));
                    });
                }
                migrate_legacy_folder_items ();
                sync_pinned_apps ();
            } catch (Error e) {
                warning ("Failed to load config: %s", e.message);
                create_default ();
            }
        }

        public void save () {
            var builder = new Json.Builder ();

            builder.begin_object ();

            builder.set_member_name ("mode");
            builder.add_string_value (dock_mode.to_string ());
            builder.set_member_name ("autohide");
            builder.add_boolean_value (autohide);
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
            builder.set_member_name ("layer");
            builder.add_int_value (layer);
            builder.set_member_name ("launcher_fallback");
            builder.add_string_value (launcher_fallback);
            builder.set_member_name ("pinned_apps");
            builder.begin_array ();
            sync_pinned_apps ();
            for (uint i = 0; i < pinned_apps.length; i++) {
                builder.add_string_value (pinned_apps[i]);
            }
            builder.end_array ();

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
            pinned_apps = new GenericArray<string> ();
            pinned_apps.add ("org.gnome.Nautilus.desktop");
            pinned_apps.add ("org.gnome.TextEditor.desktop");
            pinned_apps.add ("firefox.desktop");
            migrate_pinned_apps ();

            save ();
        }

        public static string app_item (string desktop_id) {
            return "app:" + desktop_id;
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

        public void migrate_pinned_apps () {
            dock_items = new GenericArray<string> ();
            if (pinned_apps == null) return;
            for (uint i = 0; i < pinned_apps.length; i++) {
                dock_items.add (app_item (pinned_apps[i]));
            }
        }

        public void sync_pinned_apps () {
            pinned_apps = new GenericArray<string> ();
            if (dock_items == null) return;
            for (uint i = 0; i < dock_items.length; i++) {
                if (is_app_item (dock_items[i]))
                    pinned_apps.add (item_desktop_id (dock_items[i]));
            }
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
            sync_pinned_apps ();
        }

        public void remove_dock_item (string item) {
            var result = new GenericArray<string> ();
            for (uint i = 0; i < dock_items.length; i++) {
                if (dock_items[i] != item) result.add (dock_items[i]);
            }
            dock_items = result;
            sync_pinned_apps ();
        }

        public void reorder_dock_item (string item, int position) {
            remove_dock_item (item);
            if (position < 0) position = 0;
            if (position > (int) dock_items.length) position = (int) dock_items.length;
            dock_items.insert (position, item);
            sync_pinned_apps ();
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

        public void remove_folder (string path) {
            var result = new GenericArray<DockFolderConfig> ();
            for (uint i = 0; i < dock_folders.length; i++) {
                if (dock_folders[i].path != path) result.add (dock_folders[i]);
            }
            dock_folders = result;
        }
    }
}
