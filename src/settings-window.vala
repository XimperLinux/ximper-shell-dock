namespace XimperShellDock {

    public class SettingsWindow : Adw.PreferencesWindow {

        private weak Application app;

        public SettingsWindow (Application app) {
            this.app = app;
            this.title = "Dock Settings";
            this.default_width = 500;
            this.default_height = 550;
            this.modal = false;

            build_dock_page ();
        }

        private void build_dock_page () {
            var page = new Adw.PreferencesPage ();
            page.title = "Dock";
            page.icon_name = "view-paged-symbolic";

            // Appearance group
            var appearance_group = new Adw.PreferencesGroup ();
            appearance_group.title = "Appearance";

            // Mode
            var mode_row = new Adw.ComboRow ();
            mode_row.title = "Mode";
            mode_row.subtitle = "Dock appearance style";
            var mode_list = new Gtk.StringList ({"Floating", "Pinned"});
            mode_row.model = mode_list;
            mode_row.selected = app.config.dock_mode == DockMode.FLOATING ? 0 : 1;
            mode_row.notify["selected"].connect (() => {
                app.config.dock_mode = mode_row.selected == 0 ? DockMode.FLOATING : DockMode.PINNED;
                app.config.save ();
            });
            appearance_group.add (mode_row);

            // Icon size
            var icon_row = new Adw.SpinRow.with_range (16, 96, 4);
            icon_row.title = "Icon Size";
            icon_row.subtitle = "Size of dock icons in pixels";
            icon_row.value = app.config.icon_size;
            icon_row.notify["value"].connect (() => {
                app.config.icon_size = (int) icon_row.value;
                app.config.save ();
            });
            appearance_group.add (icon_row);

            // Layer
            var layer_row = new Adw.SpinRow.with_range (0, 3, 1);
            layer_row.title = "Layer";
            layer_row.subtitle = "0 = background, 1 = bottom, 2 = top, 3 = overlay";
            layer_row.value = app.config.layer;
            layer_row.notify["value"].connect (() => {
                app.config.layer = (int) layer_row.value;
                app.config.save ();
            });
            appearance_group.add (layer_row);

            page.add (appearance_group);

            // Behavior group
            var behavior_group = new Adw.PreferencesGroup ();
            behavior_group.title = "Behavior";

            // Autohide
            var autohide_row = new Adw.SwitchRow ();
            autohide_row.title = "Autohide";
            autohide_row.subtitle = "Hide dock when not in use";
            autohide_row.active = app.config.autohide;
            autohide_row.notify["active"].connect (() => {
                app.config.autohide = autohide_row.active;
                app.config.save ();
            });
            behavior_group.add (autohide_row);

            page.add (behavior_group);

            add (page);
        }
    }
}
