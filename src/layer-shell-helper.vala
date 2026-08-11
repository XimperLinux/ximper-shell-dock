namespace XimperShellDock {

    public class LayerShellHelper {

        public static string normalize_layer_name (string value) {
            switch (value) {
                case "background":
                case "bottom":
                case "top":
                case "overlay":
                    return value;
                default:
                    return "top";
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

        public static void setup_dock_pinned (Gtk.Window window, int height, GtkLayerShell.Layer layer) {
            GtkLayerShell.init_for_window (window);
            GtkLayerShell.set_layer (window, layer);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
            GtkLayerShell.set_exclusive_zone (window, height);
            GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.ON_DEMAND);
            GtkLayerShell.set_namespace (window, "ximper-shell-dock");
        }

        public static void setup_dock_floating (Gtk.Window window, int margin, GtkLayerShell.Layer layer) {
            GtkLayerShell.init_for_window (window);
            GtkLayerShell.set_layer (window, layer);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, false);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, false);
            GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM, 16);
            GtkLayerShell.set_exclusive_zone (window, -1);
            GtkLayerShell.set_keyboard_mode (window, GtkLayerShell.KeyboardMode.ON_DEMAND);
            GtkLayerShell.set_namespace (window, "ximper-shell-dock");
        }

        public static void apply_dock_mode (Gtk.Window window, DockMode mode, int height) {
            switch (mode) {
                case DockMode.PINNED:
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.LEFT, 0);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.RIGHT, 0);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM, 0);
                    GtkLayerShell.set_exclusive_zone (window, height);
                    window.remove_css_class ("floating");
                    window.add_css_class ("pinned");
                    break;

                case DockMode.FLOATING:
                    // Anchoring both sides lets DockWindow constrain the
                    // layer surface with equal margins. Without anchors the
                    // compositor is free to grow the surface from one edge.
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
                    GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
                    GtkLayerShell.set_margin (window, GtkLayerShell.Edge.BOTTOM, 8);
                    GtkLayerShell.set_exclusive_zone (window, -1);
                    window.remove_css_class ("pinned");
                    window.add_css_class ("floating");
                    break;
            }
        }

        public static void setup_trigger (Gtk.Window window) {
            GtkLayerShell.init_for_window (window);
            GtkLayerShell.set_layer (window, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.BOTTOM, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.LEFT, true);
            GtkLayerShell.set_anchor (window, GtkLayerShell.Edge.RIGHT, true);
            GtkLayerShell.set_exclusive_zone (window, 0);
            GtkLayerShell.set_namespace (window, "ximper-shell-dock-trigger");
        }

    }
}
