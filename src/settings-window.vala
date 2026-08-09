namespace XimperShellDock {

    public class SettingsWindow : Adw.PreferencesWindow {

        private weak Application app;

        public SettingsWindow (Application app) {
            this.app = app;
            this.title = _("Dock Settings");
            this.default_width = 500;
            this.default_height = 550;
            this.modal = false;

            build_dock_page ();
        }

        private void build_dock_page () {
            var page = new Adw.PreferencesPage ();
            page.title = _("Dock");
            page.icon_name = "view-paged-symbolic";

            // Appearance group
            var appearance_group = new Adw.PreferencesGroup ();
            appearance_group.title = _("Appearance");

            // Mode
            var mode_row = new Adw.ComboRow ();
            mode_row.title = _("Mode");
            mode_row.subtitle = _("Dock appearance style");
            var mode_list = new Gtk.StringList ({_("Floating"), _("Pinned")});
            mode_row.model = mode_list;
            mode_row.selected = app.config.dock_mode == DockMode.FLOATING ? 0 : 1;
            mode_row.notify["selected"].connect (() => {
                app.config.dock_mode = mode_row.selected == 0 ? DockMode.FLOATING : DockMode.PINNED;
                app.config.save ();
            });
            appearance_group.add (mode_row);

            // Icon size
            var icon_row = new Adw.SpinRow.with_range (16, 96, 4);
            icon_row.title = _("Icon Size");
            icon_row.subtitle = _("Size of dock icons in pixels");
            icon_row.value = app.config.icon_size;
            icon_row.notify["value"].connect (() => {
                app.config.icon_size = (int) icon_row.value;
                app.config.save ();
            });
            appearance_group.add (icon_row);

            // Layer
            var layer_row = new Adw.SpinRow.with_range (0, 3, 1);
            layer_row.title = _("Layer");
            layer_row.subtitle = _("0 = background, 1 = bottom, 2 = top, 3 = overlay");
            layer_row.value = app.config.layer;
            layer_row.notify["value"].connect (() => {
                app.config.layer = (int) layer_row.value;
                app.config.save ();
            });
            appearance_group.add (layer_row);

            page.add (appearance_group);

            // Behavior group
            var behavior_group = new Adw.PreferencesGroup ();
            behavior_group.title = _("Behavior");

            // Autohide
            var autohide_row = new Adw.SwitchRow ();
            autohide_row.title = _("Autohide");
            autohide_row.subtitle = _("Hide dock when not in use");
            autohide_row.active = app.config.autohide;
            autohide_row.notify["active"].connect (() => {
                app.config.autohide = autohide_row.active;
                app.config.save ();
            });
            behavior_group.add (autohide_row);

            var trash_row = new Adw.SwitchRow ();
            trash_row.title = _("Show Trash");
            trash_row.subtitle = _("Display the system Trash at the end of the dock");
            trash_row.active = app.config.show_trash;
            trash_row.notify["active"].connect (() => {
                app.config.show_trash = trash_row.active;
                app.config.save ();
            });
            behavior_group.add (trash_row);

            // Hover magnification
            var magnify_row = new Adw.SwitchRow ();
            magnify_row.title = _("Magnify icons on hover");
            magnify_row.subtitle = _("Animate nearby icons when moving the pointer over the dock");
            magnify_row.active = app.config.magnify_on_hover;
            magnify_row.notify["active"].connect (() => {
                app.config.magnify_on_hover = magnify_row.active;
                app.config.save ();
            });
            behavior_group.add (magnify_row);

            var bounce_row = new Adw.SwitchRow ();
            bounce_row.title = _("Bounce while launching");
            bounce_row.subtitle = _("Bounce an app icon until its window appears");
            bounce_row.active = app.config.bounce_on_launch;
            bounce_row.notify["active"].connect (() => {
                app.config.bounce_on_launch = bounce_row.active;
                app.config.save ();
            });
            behavior_group.add (bounce_row);

            var bounce_speed_row = new Adw.SpinRow.with_range (100, 500, 10);
            bounce_speed_row.title = _("Bounce speed");
            bounce_speed_row.subtitle = _("Duration of the upward launch bounce in milliseconds");
            bounce_speed_row.value = app.config.bounce_duration;
            bounce_speed_row.notify["value"].connect (() => {
                app.config.bounce_duration = (int) bounce_speed_row.value;
                app.config.save ();
            });
            behavior_group.add (bounce_speed_row);

            var magnify_scale_row = new Adw.SpinRow.with_range (110, 200, 5);
            magnify_scale_row.title = _("Maximum magnification");
            magnify_scale_row.subtitle = _("Largest icon size while the pointer is over it");
            magnify_scale_row.value = app.config.magnify_scale;
            magnify_scale_row.notify["value"].connect (() => {
                app.config.magnify_scale = (int) magnify_scale_row.value;
                app.config.save ();
            });
            behavior_group.add (magnify_scale_row);

            var magnify_radius_row = new Adw.SpinRow.with_range (1.0, 5.0, 0.25);
            magnify_radius_row.title = _("Neighbour reach");
            magnify_radius_row.subtitle = _("How many icon widths the wave affects on each side");
            magnify_radius_row.value = app.config.magnify_radius;
            magnify_radius_row.notify["value"].connect (() => {
                app.config.magnify_radius = magnify_radius_row.value;
                app.config.save ();
            });
            behavior_group.add (magnify_radius_row);

            var magnify_duration_row = new Adw.SpinRow.with_range (50, 400, 10);
            magnify_duration_row.title = _("Animation response");
            magnify_duration_row.subtitle = _("Time in milliseconds; lower values react faster");
            magnify_duration_row.value = app.config.magnify_animation_duration;
            magnify_duration_row.notify["value"].connect (() => {
                app.config.magnify_animation_duration = (int) magnify_duration_row.value;
                app.config.save ();
            });
            behavior_group.add (magnify_duration_row);

            page.add (behavior_group);

            add (page);
        }
    }
}
