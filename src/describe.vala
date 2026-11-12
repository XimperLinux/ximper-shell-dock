namespace XimperShellDock {

    public string describe_json (ConfigManager config, bool running = true) {
        var builder = new Json.Builder ();
        builder.begin_object ();

        builder.set_member_name ("api_version");
        builder.add_int_value (1);
        builder.set_member_name ("write_protocol");
        builder.add_string_value ("locked-json-v1");
        if (!FileUtils.test (config.config_file, FileTest.EXISTS)) {
            builder.set_member_name ("initial_config");
            builder.add_value (config.snapshot ());
        }
        builder.set_member_name ("config");
        builder.begin_object ();
        builder.set_member_name ("mode"); builder.add_string_value (config.dock_mode.to_string ());
        builder.set_member_name ("position"); builder.add_string_value (config.dock_position.to_string ());
        builder.set_member_name ("show_trash"); builder.add_boolean_value (config.show_trash);
        builder.set_member_name ("magnify_on_hover"); builder.add_boolean_value (config.magnify_on_hover);
        builder.set_member_name ("bounce_on_launch"); builder.add_boolean_value (config.bounce_on_launch);
        builder.set_member_name ("bounce_duration"); builder.add_int_value (config.bounce_duration);
        builder.set_member_name ("magnify_scale"); builder.add_int_value (config.magnify_scale);
        builder.set_member_name ("magnify_radius"); builder.add_double_value (config.magnify_radius);
        builder.set_member_name ("magnify_animation_duration"); builder.add_int_value (config.magnify_animation_duration);
        builder.set_member_name ("icon_size"); builder.add_int_value (config.icon_size);
        builder.set_member_name ("hide_delay"); builder.add_int_value (config.hide_delay);
        builder.set_member_name ("floating_margin"); builder.add_int_value (config.floating_margin);
        builder.set_member_name ("layer"); builder.add_string_value (config.layer);
        builder.set_member_name ("launcher_fallback"); builder.add_string_value (config.launcher_fallback);
        builder.set_member_name ("monitors");
        builder.begin_array ();
        for (uint i = 0; i < config.monitor_ids.length; i++) builder.add_string_value (config.monitor_ids[i]);
        builder.end_array ();
        builder.set_member_name ("dock_items");
        builder.begin_array ();
        for (uint i = 0; i < config.dock_items.length; i++) builder.add_string_value (config.dock_items[i]);
        builder.end_array ();
        builder.set_member_name ("dock_folders");
        builder.begin_array ();
        for (uint i = 0; i < config.dock_folders.length; i++) {
            var folder = config.dock_folders[i];
            builder.begin_object ();
            builder.set_member_name ("path"); builder.add_string_value (folder.path);
            builder.set_member_name ("display"); builder.add_string_value (folder.display_type);
            builder.set_member_name ("view"); builder.add_string_value (folder.view_type);
            builder.set_member_name ("sort"); builder.add_string_value (folder.sort_type);
            builder.set_member_name ("columns"); builder.add_int_value (folder.grid_columns);
            builder.set_member_name ("rows"); builder.add_int_value (folder.grid_rows);
            builder.set_member_name ("item_size"); builder.add_int_value (folder.item_size);
            builder.set_member_name ("favorites");
            builder.begin_array ();
            for (uint j = 0; j < folder.favorite_uris.length; j++) builder.add_string_value (folder.favorite_uris[j]);
            builder.end_array ();
            builder.end_object ();
        }
        builder.end_array ();
        builder.end_object ();

        builder.set_member_name ("runtime");
        builder.begin_object ();
        builder.set_member_name ("running"); builder.add_boolean_value (running);
        builder.end_object ();
        builder.set_member_name ("paths");
        builder.begin_object ();
        builder.set_member_name ("config"); builder.add_string_value (config.config_file);
        builder.end_object ();

        builder.set_member_name ("metadata");
        builder.begin_object ();
        builder.set_member_name ("properties");
        builder.begin_object ();
        builder.set_member_name ("monitors");
        builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("array");
        builder.set_member_name ("items"); builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("string"); builder.end_object ();
        builder.end_object ();
        builder.set_member_name ("dock_items");
        builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("array");
        builder.set_member_name ("items"); builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("string"); builder.end_object ();
        builder.set_member_name ("readOnly"); builder.add_boolean_value (true);
        builder.end_object ();
        builder.set_member_name ("dock_folders");
        builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("array");
        builder.set_member_name ("items"); builder.begin_object ();
        builder.set_member_name ("type"); builder.add_string_value ("object"); builder.end_object ();
        builder.set_member_name ("readOnly"); builder.add_boolean_value (true);
        builder.end_object ();
        add_enum_property (builder, "mode", "Dock mode", "floating", { "floating", "pinned" });
        add_enum_property (builder, "position", "Dock position", "bottom", { "bottom", "top", "left", "right" });
        add_boolean_property (builder, "show_trash", "Show Trash", false);
        add_boolean_property (builder, "magnify_on_hover", "Magnify icons on hover", false);
        add_boolean_property (builder, "bounce_on_launch", "Bounce icon on launch", false);
        add_integer_property (builder, "bounce_duration", "Bounce duration", 200, 100, 500);
        add_integer_property (builder, "magnify_scale", "Magnification scale", 135, 100, 200);
        add_number_property (builder, "magnify_radius", "Magnification radius", 2.0, 1.0, 8.0);
        add_integer_property (builder, "magnify_animation_duration", "Magnification animation duration", 120, 0, 1000);
        add_integer_property (builder, "icon_size", "Icon size", 32, 16, 128);
        add_integer_property (builder, "hide_delay", "Hide delay", 300, 0, 5000);
        add_integer_property (builder, "floating_margin", "Floating dock edge margin", 8, 0, 128);
        add_enum_property (builder, "layer", "Layer-shell layer", "top", { "background", "bottom", "top", "overlay" });
        add_string_property (builder, "launcher_fallback", "Fallback launcher command", "wofi --show drun");
        builder.end_object ();
        builder.end_object ();
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.set_root (builder.get_root ());
        generator.set_pretty (true);
        return generator.to_data (null) + "\n";
    }

    private void add_property (Json.Builder builder, string name, string title, string type) {
        builder.set_member_name (name);
        builder.begin_object ();
        builder.set_member_name ("title"); builder.add_string_value (title);
        builder.set_member_name ("type"); builder.add_string_value (type);
    }

    private void add_boolean_property (Json.Builder builder, string name, string title, bool default_value) {
        add_property (builder, name, title, "boolean");
        builder.set_member_name ("default"); builder.add_boolean_value (default_value);
        builder.end_object ();
    }

    private void add_string_property (Json.Builder builder, string name, string title, string default_value) {
        add_property (builder, name, title, "string");
        builder.set_member_name ("default"); builder.add_string_value (default_value);
        builder.end_object ();
    }

    private void add_enum_property (Json.Builder builder, string name, string title, string default_value, string[] values) {
        add_property (builder, name, title, "string");
        builder.set_member_name ("default"); builder.add_string_value (default_value);
        builder.set_member_name ("enum"); builder.begin_array ();
        foreach (var value in values) builder.add_string_value (value);
        builder.end_array (); builder.end_object ();
    }

    private void add_integer_property (Json.Builder builder, string name, string title, int default_value, int minimum, int maximum) {
        add_property (builder, name, title, "integer");
        builder.set_member_name ("default"); builder.add_int_value (default_value);
        builder.set_member_name ("minimum"); builder.add_int_value (minimum);
        builder.set_member_name ("maximum"); builder.add_int_value (maximum);
        builder.end_object ();
    }

    private void add_number_property (Json.Builder builder, string name, string title, double default_value, double minimum, double maximum) {
        add_property (builder, name, title, "number");
        builder.set_member_name ("default"); builder.add_double_value (default_value);
        builder.set_member_name ("minimum"); builder.add_double_value (minimum);
        builder.set_member_name ("maximum"); builder.add_double_value (maximum);
        builder.end_object ();
    }
}
