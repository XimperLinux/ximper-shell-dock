namespace XimperShellDock {

    public class FolderSettingsWindow : Adw.PreferencesWindow {

        private weak ConfigManager config;
        private weak DockFolderConfig folder;

        public signal void changed ();

        public FolderSettingsWindow (ConfigManager config, DockFolderConfig folder) {
            this.config = config;
            this.folder = folder;
            title = _("Stack Settings");
            default_width = 420;
            default_height = 520;
            modal = false;

            var page = new Adw.PreferencesPage ();
            page.title = Path.get_basename (folder.path);
            page.icon_name = "folder-symbolic";
            var group = new Adw.PreferencesGroup ();
            group.title = _("Folder in Dock");

            var display = new Adw.ComboRow ();
            display.title = _("Appearance");
            display.subtitle = _("Show a plain folder or a preview stack");
            display.model = new Gtk.StringList ({_("Folder"), _("Stack")});
            display.selected = folder.display_type == "folder" ? 0 : 1;
            display.notify["selected"].connect (() => {
                folder.display_type = display.selected == 0 ? "folder" : "stack";
                save_changes ();
            });
            group.add (display);

            var view = new Adw.ComboRow ();
            view.title = _("Open as");
            view.subtitle = _("Choose a clear, standard GTK layout");
            view.model = new Gtk.StringList ({_("Grid"), _("List")});
            if (folder.view_type == "list") view.selected = 1;
            else view.selected = 0;
            view.notify["selected"].connect (() => {
                folder.view_type = view.selected == 1 ? "list" : "grid";
                save_changes ();
            });
            group.add (view);

            var layout_group = new Adw.PreferencesGroup ();
            layout_group.title = _("Grid Layout");
            layout_group.description = _("Controls apply when the folder is opened as a grid.");

            var columns = new Adw.SpinRow.with_range (1, 12, 1);
            columns.title = _("Columns");
            columns.subtitle = _("Items in each row");
            columns.value = folder.grid_columns;
            columns.notify["value"].connect (() => {
                folder.grid_columns = ((int) columns.value).clamp (1, 12);
                save_changes ();
            });
            layout_group.add (columns);

            var rows = new Adw.SpinRow.with_range (1, 10, 1);
            rows.title = _("Rows");
            rows.subtitle = _("Visible rows before scrolling");
            rows.value = folder.grid_rows;
            rows.notify["value"].connect (() => {
                folder.grid_rows = ((int) rows.value).clamp (1, 10);
                save_changes ();
            });
            layout_group.add (rows);

            var item_group = new Adw.PreferencesGroup ();
            item_group.title = _("Item Appearance");
            item_group.description = _("Applies to thumbnails and icons in both grid and list views.");

            var item_size = new Adw.SpinRow.with_range (32, 128, 4);
            item_size.title = _("Item Size");
            item_size.subtitle = _("Thumbnail and icon size in pixels");
            item_size.value = folder.item_size;
            item_size.notify["value"].connect (() => {
                folder.item_size = ((int) item_size.value).clamp (32, 128);
                save_changes ();
            });
            item_group.add (item_size);

            var sort = new Adw.ComboRow ();
            sort.title = _("Sort by");
            sort.model = new Gtk.StringList ({_("Name"), _("Date Modified"), _("Kind")});
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
            page.add (layout_group);
            page.add (item_group);
            add (page);
        }

        private void save_changes () {
            config.save ();
            changed ();
        }
    }
}
