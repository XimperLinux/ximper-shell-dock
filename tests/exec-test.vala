// AppEntry only needs this data model for the command-line parser test.
namespace XimperShellDock {
    public class RunningApp {
        public string app_class = "";
        public string title = "";
    }
}

private void test_field_codes () {
    assert (XimperShellDock.AppEntry.strip_field_codes (
        "program --format=%% --file=%f") == "program --format=% --file=");
    assert (XimperShellDock.AppEntry.strip_field_codes (
        "program 100%%") == "program 100%");
}

private void test_invalid_dbus_name_fallback () {
    try {
        var dir = DirUtils.make_tmp ("ximper-dock-launch-test-XXXXXX");
        var desktop = Path.build_filename (dir, "max.desktop");
        var marker = Path.build_filename (dir, "launched");
        FileUtils.set_contents (desktop, "[Desktop Entry]\nType=Application\nName=Test MAX\n" +
            "Exec=/usr/bin/touch " + marker + "\nDBusActivatable=true\n");
        var info = new DesktopAppInfo.from_filename (desktop);
        assert (info != null);
        var entry = new XimperShellDock.AppEntry (info);
        assert (!DBus.is_name (XimperShellDock.AppEntry.desktop_entry_name (entry.desktop_id)));
        assert (entry.launch ());
        for (int i = 0; i < 100 && !FileUtils.test (marker, FileTest.EXISTS); i++)
            Thread.usleep (20000);
        assert (FileUtils.test (marker, FileTest.EXISTS));
    } catch (Error e) {
        error ("Test setup failed: %s", e.message);
    }
}

private void test_missing_service_fallback () {
    try {
        var dir = DirUtils.make_tmp ("ximper-dock-bus-test-XXXXXX");
        var desktop = Path.build_filename (dir,
            "org.ximperlinux.LaunchTest_" + Uuid.string_random ().replace ("-", "_") + ".desktop");
        var marker = Path.build_filename (dir, "fallback-launched");
        FileUtils.set_contents (desktop, "[Desktop Entry]\nType=Application\nName=Test D-Bus fallback\n" +
            "Exec=/usr/bin/touch " + marker + " %U\nDBusActivatable=true\n");
        var info = new DesktopAppInfo.from_filename (desktop);
        assert (info != null);
        var entry = new XimperShellDock.AppEntry (info);
        Test.expect_message (null, LogLevelFlags.LEVEL_WARNING,
            "*D-Bus activation failed*falling back to Exec*");
        assert (entry.launch ());
        for (int i = 0; i < 250 && !FileUtils.test (marker, FileTest.EXISTS); i++) {
            while (MainContext.default ().iteration (false)) {}
            Thread.usleep (20000);
        }
        assert (FileUtils.test (marker, FileTest.EXISTS));
        Test.assert_expected_messages ();
    } catch (Error e) {
        error ("Test setup failed: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/desktop-entry/exec-field-codes", test_field_codes);
    Test.add_func ("/desktop-entry/invalid-dbus-name-fallback", test_invalid_dbus_name_fallback);
    Test.add_func ("/desktop-entry/missing-service-fallback", test_missing_service_fallback);
    return Test.run ();
}
