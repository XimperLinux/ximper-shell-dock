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
    } catch (Error e) {
        error ("Test setup failed: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/config/invalid-reload", test_invalid_reload);
    return Test.run ();
}
