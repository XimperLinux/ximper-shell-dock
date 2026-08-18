namespace XimperShellDock {

    public class WaylandOutputInfo : Object {
        public Wl.Output? output;
        public string? name;
        public Wl.OutputTransform transform = Wl.OutputTransform.NORMAL;
        public int mode_width = 0;
        public int mode_height = 0;
        public int scale = 1;

        public WaylandOutputInfo (owned Wl.Output output) {
            this.output = (owned) output;
        }

        public bool has_size () {
            return mode_width > 0 && mode_height > 0 && scale > 0;
        }

        public bool transform_swaps_axes () {
            return transform == Wl.OutputTransform._90 ||
                   transform == Wl.OutputTransform._270 ||
                   transform == Wl.OutputTransform.FLIPPED_90 ||
                   transform == Wl.OutputTransform.FLIPPED_270;
        }
    }

    internal class WaylandOutputQuery : Object {
        public GenericArray<WaylandOutputInfo> outputs = new GenericArray<WaylandOutputInfo> ();
    }

    public class WaylandOutputInfoProvider {
        private const uint32 WL_OUTPUT_MODE_CURRENT = 0x1;
        private static bool listeners_initialized = false;
        private static Wl.RegistryListener registry_listener;
        private static Wl.OutputListener output_listener;

        private static void ensure_listeners () {
            if (listeners_initialized) return;
            registry_listener.global = on_registry_global;
            registry_listener.global_remove = on_registry_global_remove;
            output_listener.geometry = on_output_geometry;
            output_listener.mode = on_output_mode;
            output_listener.done = on_output_done;
            output_listener.scale = on_output_scale;
            output_listener.name = on_output_name;
            output_listener.description = on_output_description;
            listeners_initialized = true;
        }

        public static bool get_logical_size (string? connector, out int width, out int height) {
            width = 0;
            height = 0;
            if (connector == null || connector.length == 0) return false;

            ensure_listeners ();
            var display = Wl.display_connect ();
            if (display == null) return false;

            var query = new WaylandOutputQuery ();
            var registry = display.get_registry ();
            if (registry == null) return false;

            Wl.registry_add_listener (registry, ref registry_listener, query);
            if (display.roundtrip () < 0 || display.roundtrip () < 0) return false;

            for (uint i = 0; i < query.outputs.length; i++) {
                var output = query.outputs[i];
                if (output.name != connector || !output.has_size ()) continue;

                int raw_width = output.mode_width / output.scale;
                int raw_height = output.mode_height / output.scale;
                if (output.transform_swaps_axes ()) {
                    width = raw_height;
                    height = raw_width;
                } else {
                    width = raw_width;
                    height = raw_height;
                }
                return width > 0 && height > 0;
            }

            return false;
        }

        private static void on_registry_global (void* data, Wl.Registry registry,
                                                uint32 name, string iface, uint32 version) {
            if (iface != "wl_output") return;

            var output = registry.bind<Wl.Output> (
                name, ref Wl.output_interface, uint32.min (version, 4)
            );
            if (output == null) return;

            var info = new WaylandOutputInfo ((owned) output);
            Wl.output_add_listener (info.output, ref output_listener, info);
            ((WaylandOutputQuery) data).outputs.add (info);
        }

        private static void on_registry_global_remove (void* data, Wl.Registry registry, uint32 name) {}

        private static void on_output_geometry (void* data, Wl.Output output, int32 x, int32 y,
                                                int32 physical_width, int32 physical_height,
                                                int32 subpixel, string make, string model,
                                                int32 transform) {
            ((WaylandOutputInfo) data).transform = (Wl.OutputTransform) transform;
        }

        private static void on_output_mode (void* data, Wl.Output output, uint32 flags,
                                            int32 width, int32 height, int32 refresh) {
            var info = (WaylandOutputInfo) data;
            if ((flags & WL_OUTPUT_MODE_CURRENT) == 0 && info.has_size ()) return;
            info.mode_width = width;
            info.mode_height = height;
        }

        private static void on_output_done (void* data, Wl.Output output) {}

        private static void on_output_scale (void* data, Wl.Output output, int32 factor) {
            if (factor > 0) ((WaylandOutputInfo) data).scale = factor;
        }

        private static void on_output_name (void* data, Wl.Output output, string name) {
            ((WaylandOutputInfo) data).name = name;
        }

        private static void on_output_description (void* data, Wl.Output output, string description) {}
    }
}
