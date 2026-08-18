namespace XimperShellDock {

    public class LayerShellHelper {

        public static string normalize_layer_name (string value) {
            switch (value) {
                case "background": case "bottom": case "top": case "overlay": return value;
                default: return "top";
            }
        }

        public static string layer_name_from_legacy (int value) {
            switch (value.clamp (0, 3)) {
                case 0: return "background";
                case 1: return "bottom";
                case 3: return "overlay";
                default: return "top";
            }
        }

        public static GtkLayerShell.Layer parse_layer (string value) {
            switch (normalize_layer_name (value)) {
                case "background": return GtkLayerShell.Layer.BACKGROUND;
                case "bottom": return GtkLayerShell.Layer.BOTTOM;
                case "overlay": return GtkLayerShell.Layer.OVERLAY;
                default: return GtkLayerShell.Layer.TOP;
            }
        }

        private static void clear_edges (Gtk.Window window) {
            GtkLayerShell.Edge[] edges = { GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                                           GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT };
            foreach (var edge in edges) {
                GtkLayerShell.set_anchor (window, edge, false);
                GtkLayerShell.set_margin (window, edge, 0);
            }
        }

        public static void setup_dock_floating (Gtk.Window window, int margin,
                                                GtkLayerShell.Layer layer,
                                                DockPosition position) {
            GtkLayerShell.init_for_window (window);
            GtkLayerShell.set_layer (window, layer);
            GtkLayerShell.set_exclusive_zone (window, -1);
            GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.ON_DEMAND);
            GtkLayerShell.set_namespace (window, "ximper-shell-dock");
            apply_dock_mode (window, DockMode.FLOATING, 0, margin, position);
        }

        public static void apply_dock_mode (Gtk.Window window, DockMode mode, int thickness,
                                            int floating_margin, DockPosition position) {
            clear_edges (window);
            GtkLayerShell.Edge edge = GtkLayerShell.Edge.BOTTOM;
            GtkLayerShell.Edge span_start = GtkLayerShell.Edge.LEFT;
            GtkLayerShell.Edge span_end = GtkLayerShell.Edge.RIGHT;
            if (position == DockPosition.TOP) {
                edge = GtkLayerShell.Edge.TOP;
            } else if (position == DockPosition.LEFT) {
                edge = GtkLayerShell.Edge.LEFT;
                span_start = GtkLayerShell.Edge.TOP; span_end = GtkLayerShell.Edge.BOTTOM;
            } else if (position == DockPosition.RIGHT) {
                edge = GtkLayerShell.Edge.RIGHT;
                span_start = GtkLayerShell.Edge.TOP; span_end = GtkLayerShell.Edge.BOTTOM;
            }
            GtkLayerShell.set_anchor (window, edge, true);
            GtkLayerShell.set_anchor (window, span_start, true);
            GtkLayerShell.set_anchor (window, span_end, true);
            GtkLayerShell.set_margin (window, edge,
                mode == DockMode.FLOATING ? floating_margin : 0);
            GtkLayerShell.set_exclusive_zone (window,
                mode == DockMode.PINNED ? thickness : -1);
            window.remove_css_class (mode == DockMode.PINNED ? "floating" : "pinned");
            window.add_css_class (mode == DockMode.PINNED ? "pinned" : "floating");
        }
    }
}
