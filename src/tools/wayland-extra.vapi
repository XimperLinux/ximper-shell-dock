[CCode (cheader_filename = "wayland-client.h")]
namespace Wl {
    [CCode (cname = "wl_output_interface")]
    public static Interface output_interface;

    [CCode (cname = "wl_display_connect")]
    public static Display? display_connect (string? name = null);

    [CCode (cname = "wl_registry_add_listener")]
    public static int registry_add_listener (Registry registry, ref RegistryListener listener, void* data);

    [CCode (cname = "wl_output_add_listener")]
    public static int output_add_listener (Output output, ref OutputListener listener, void* data);
}
