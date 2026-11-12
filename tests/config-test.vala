using XimperShellDock;

private void test_invalid_reload () {
    try {
    var dir = DirUtils.make_tmp ("ximper-dock-config-test-XXXXXX");
    Environment.set_variable ("XDG_CONFIG_HOME", dir, true);

    var config = new ConfigManager ();
    config.load ();
    config.icon_size = 57;
    var item_count = config.dock_items.length;

    string[] invalid = { "{invalid json", "[]" };
    foreach (var value in invalid) {
        FileUtils.set_contents (config.config_file, value);
        Test.expect_message (null, LogLevelFlags.LEVEL_WARNING, "*Failed to load config*");
        config.load ();
        Test.assert_expected_messages ();
        assert (config.icon_size == 57);
        assert (config.dock_items.length == item_count);
    }

    FileUtils.set_contents (config.config_file, "{\"bounce_duration\":-900}");
    config.load ();
    assert (config.bounce_duration == 100);
    FileUtils.set_contents (config.config_file, "{\"icon_size\":48,\"extension\":true}");
    config.add_folder ("/home/example/Documents");
    config.save ();
    var parser = new Json.Parser ();
    parser.load_from_file (config.config_file);
    var saved = parser.get_root ().get_object ();
    assert (saved.get_int_member ("icon_size") == 48);
    assert (saved.get_boolean_member ("extension"));
    assert (saved.get_array_member ("dock_folders").get_length () == 1);
    } catch (Error e) {
        error ("Test setup failed: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/config/invalid-reload", test_invalid_reload);
    return Test.run ();
}
