namespace XimperShellDock {

    public class DockFolderConfig : Object {
        public string path;
        public string display_type;
        public string view_type;
        public string sort_type;
        // These are deliberately plain fields: GenericArray properties are
        // not safe in Vala-generated GObject code.
        public GenericArray<string> favorite_uris;
        public int grid_columns;
        public int grid_rows;
        public int item_size;

        public DockFolderConfig (string path, string display_type = "stack",
                                 string view_type = "grid", string sort_type = "name",
                                 int grid_columns = 4, int grid_rows = 3,
                                 int item_size = 56) {
            this.path = path;
            this.display_type = display_type;
            this.view_type = view_type == "list" ? "list" : "grid";
            this.sort_type = sort_type;
            this.grid_columns = grid_columns.clamp (1, 12);
            this.grid_rows = grid_rows.clamp (1, 10);
            this.item_size = item_size.clamp (32, 128);
            favorite_uris = new GenericArray<string> ();
        }
    }

    public enum DockPosition {
        BOTTOM,
        TOP,
        LEFT,
        RIGHT;

        public static DockPosition from_string (string val) {
            if (val == "top") return TOP;
            if (val == "left") return LEFT;
            if (val == "right") return RIGHT;
            return BOTTOM;
        }

        public string to_string () {
            if (this == TOP) return "top";
            if (this == LEFT) return "left";
            if (this == RIGHT) return "right";
            return "bottom";
        }

        public bool is_vertical () { return this == LEFT || this == RIGHT; }
        public Gtk.Orientation orientation () {
            return is_vertical () ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL;
        }
        public Gtk.PositionType inward_popover_position () {
            if (this == LEFT) return Gtk.PositionType.RIGHT;
            if (this == RIGHT) return Gtk.PositionType.LEFT;
            return this == TOP ? Gtk.PositionType.BOTTOM : Gtk.PositionType.TOP;
        }
    }

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
}
