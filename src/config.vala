namespace XimperShellDock {

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
        public int icon_size { get; set; default = 48; }
        public int layer { get; set; default = 2; }
        public GenericArray<string> pinned_apps;

        private string config_path;

        public ConfigManager () {
            pinned_apps = new GenericArray<string> ();

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
                if (root.has_member ("icon_size"))
                    icon_size = (int) root.get_int_member ("icon_size");
                if (root.has_member ("layer"))
                    layer = (int) root.get_int_member ("layer");

                if (root.has_member ("pinned_apps")) {
                    pinned_apps = new GenericArray<string> ();
                    var arr = root.get_array_member ("pinned_apps");
                    arr.foreach_element ((array, i, node) => {
                        pinned_apps.add (node.get_string ());
                    });
                }
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
            builder.set_member_name ("icon_size");
            builder.add_int_value (icon_size);
            builder.set_member_name ("layer");
            builder.add_int_value (layer);
            builder.set_member_name ("pinned_apps");
            builder.begin_array ();
            if (pinned_apps == null) pinned_apps = new GenericArray<string> ();
            for (uint i = 0; i < pinned_apps.length; i++) {
                builder.add_string_value (pinned_apps[i]);
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

            save ();
        }
    }
}
