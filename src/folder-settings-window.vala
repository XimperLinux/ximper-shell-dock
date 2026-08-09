namespace XimperShellDock {

    public class FolderSettingsWindow : Adw.PreferencesWindow {

        private weak ConfigManager config;
        private weak DockFolderConfig folder;

        public signal void changed ();

        public FolderSettingsWindow (ConfigManager config, DockFolderConfig folder) {
            this.config = config;
            this.folder = folder;
            title = "Stack Settings";
            default_width = 420;
            default_height = 360;
            modal = false;

            var page = new Adw.PreferencesPage ();
            page.title = Path.get_basename (folder.path);
            page.icon_name = "folder-symbolic";
            var group = new Adw.PreferencesGroup ();
            group.title = "Folder in Dock";

            var display = new Adw.ComboRow ();
            display.title = "Appearance";
            display.subtitle = "Show a plain folder or a preview stack";
            display.model = new Gtk.StringList ({"Folder", "Stack"});
            display.selected = folder.display_type == "folder" ? 0 : 1;
            display.notify["selected"].connect (() => {
                folder.display_type = display.selected == 0 ? "folder" : "stack";
                save_changes ();
            });
            group.add (display);

            var view = new Adw.ComboRow ();
            view.title = "Open as";
            view.subtitle = "How the folder contents are displayed";
            view.model = new Gtk.StringList ({"Grid", "List", "Fan"});
            if (folder.view_type == "list") view.selected = 1;
            else if (folder.view_type == "fan") view.selected = 2;
            else view.selected = 0;
            view.notify["selected"].connect (() => {
                folder.view_type = view.selected == 1 ? "list" :
                    (view.selected == 2 ? "fan" : "grid");
                save_changes ();
            });
            group.add (view);

            var sort = new Adw.ComboRow ();
            sort.title = "Sort by";
            sort.model = new Gtk.StringList ({"Name", "Date Modified", "Kind"});
            if (folder.sort_type == "modified") sort.selected = 1;
            else if (folder.sort_type == "kind") sort.selected = 2;
            else sort.selected = 0;
            sort.notify["selected"].connect (() => {
                folder.sort_type = sort.selected == 1 ? "modified" :
                    (sort.selected == 2 ? "kind" : "name");
                save_changes ();
            });
            group.add (sort);

            page.add (group);
            add (page);
        }

        private void save_changes () {
            config.save ();
            changed ();
        }
    }
}
