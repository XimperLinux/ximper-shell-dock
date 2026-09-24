// AppEntry only needs this data model for the command-line parser test.
namespace XimperShellDock {
    public class RunningApp {
        public string app_class = "";
        public string title = "";
    }
}

[DBus (name = "org.freedesktop.Application")]
private class FakeApplication : Object {
    public bool activated = false;
    public void activate (HashTable<string, Variant> platform_data) {
        activated = true;
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

private void test_desktop_filename_fallback () {
    try {
        var dir = DirUtils.make_tmp ("ximper-dock-filename-test-XXXXXX");
        var desktop = Path.build_filename (dir,
            "org.ximperlinux.LaunchFilenameTest_" + Uuid.string_random ().replace ("-", "_") + ".desktop");
        var marker = Path.build_filename (dir, "copied-desktop");
        FileUtils.set_contents (desktop, "[Desktop Entry]\nType=Application\nName=Test filename\n" +
            "Exec=/usr/bin/cp %k " + marker + "\nDBusActivatable=true\n");
        var info = new DesktopAppInfo.from_filename (desktop);
        assert (info != null);
        Test.expect_message (null, LogLevelFlags.LEVEL_WARNING,
            "*D-Bus activation failed*falling back to Exec*");
        assert (new XimperShellDock.AppEntry (info).launch ());
        for (int i = 0; i < 250 && !FileUtils.test (marker, FileTest.EXISTS); i++) {
            while (MainContext.default ().iteration (false)) {}
            Thread.usleep (20000);
        }
        string copied;
        FileUtils.get_contents (marker, out copied);
        assert (copied.contains ("DBusActivatable=true"));
        Test.assert_expected_messages ();
    } catch (Error e) {
        error ("Filename test failed: %s", e.message);
    }
}

private void test_valid_dbus_activation () {
    try {
        var dir = DirUtils.make_tmp ("ximper-dock-valid-bus-test-XXXXXX");
        var desktop = Path.build_filename (dir, "org.ximperlinux.LaunchTestService.desktop");
        var marker = Path.build_filename (dir, "exec-should-not-run");
        FileUtils.set_contents (desktop, "[Desktop Entry]\nType=Application\nName=Test valid D-Bus\n" +
            "Exec=/usr/bin/touch " + marker + "\nDBusActivatable=true\n");
        var conn = Bus.get_sync (BusType.SESSION);
        var service = new FakeApplication ();
        var registration = conn.register_object ("/org/ximperlinux/LaunchTestService", service);
        conn.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "RequestName",
            new Variant ("(su)", "org.ximperlinux.LaunchTestService", 0u),
            new VariantType ("(u)"), DBusCallFlags.NONE, 1000);
        var info = new DesktopAppInfo.from_filename (desktop);
        assert (info != null);
        assert (new XimperShellDock.AppEntry (info).launch ());
        for (int i = 0; i < 100 && !service.activated; i++) {
            while (MainContext.default ().iteration (false)) {}
            Thread.usleep (20000);
        }
        assert (service.activated);
        assert (!FileUtils.test (marker, FileTest.EXISTS));
        conn.unregister_object (registration);
    } catch (Error e) {
        error ("D-Bus test setup failed: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    var bus = new TestDBus (TestDBusFlags.NONE);
    bus.up ();
    Test.add_func ("/desktop-entry/exec-field-codes", test_field_codes);
    Test.add_func ("/desktop-entry/invalid-dbus-name-fallback", test_invalid_dbus_name_fallback);
    Test.add_func ("/desktop-entry/missing-service-fallback", test_missing_service_fallback);
    Test.add_func ("/desktop-entry/filename-fallback", test_desktop_filename_fallback);
    Test.add_func ("/desktop-entry/valid-dbus-activation", test_valid_dbus_activation);
    var result = Test.run ();
    bus.down ();
    return result;
}
