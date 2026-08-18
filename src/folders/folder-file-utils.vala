namespace XimperShellDock {

    internal class FolderFileUtils : Object {
        public static void sort_entries (GenericArray<FileInfo> entries, string sort_type) {
            for (uint i = 0; i < entries.length; i++) {
                for (uint j = i + 1; j < entries.length; j++) {
                    if (compare_file_info (entries[i], entries[j], sort_type) > 0) {
                        var item = entries[i];
                        entries[i] = entries[j];
                        entries[j] = item;
                    }
                }
            }
        }

        private static int compare_file_info (FileInfo a, FileInfo b, string sort_type) {
            if (sort_type == "kind")
                return strcmp (a.get_content_type () ?? "", b.get_content_type () ?? "");
            if (sort_type == "modified") {
                var a_time = a.get_modification_date_time ();
                var b_time = b.get_modification_date_time ();
                var a_value = a_time != null ? a_time.to_unix () : 0;
                var b_value = b_time != null ? b_time.to_unix () : 0;
                return a_value == b_value ? 0 : (a_value > b_value ? -1 : 1);
            }
            return strcmp (a.get_display_name (), b.get_display_name ());
        }

        public static File? get_cached_thumbnail (File file) {
            var uri = file.get_uri ();
            var digest = Checksum.compute_for_string (ChecksumType.MD5, uri);
            // File managers choose their cache bucket independently. In
            // particular, this folder has only 256px thumbnails in `large`;
            // looking at `normal` alone incorrectly reports no preview.
            string[] buckets = { "normal", "large" };
            for (int i = 0; i < buckets.length; i++) {
                var path = Path.build_filename (
                    Environment.get_user_cache_dir (), "thumbnails", buckets[i], digest + ".png"
                );
                if (FileUtils.test (path, FileTest.EXISTS)) return File.new_for_path (path);
            }
            return null;
        }

        public static void open_file (File file, FileInfo info) {
            try {
                var content_type = info.get_content_type ();
                if (content_type == null) {
                    warning ("Cannot determine the content type of %s", file.get_uri ());
                    return;
                }
                var app_info = AppInfo.get_default_for_type (content_type, false);
                if (app_info == null) {
                    warning ("No application is registered for %s", content_type);
                    return;
                }
                var uris = new List<string> ();
                uris.append (file.get_uri ());
                var context = Gdk.Display.get_default ().get_app_launch_context ();
                app_info.launch_uris (uris, context);
            } catch (Error e) {
                warning ("Cannot open %s: %s", file.get_uri (), e.message);
            }
        }

        public static void open_in_file_manager (string folder_path) {
            try {
                AppInfo.launch_default_for_uri (File.new_for_path (folder_path).get_uri (), null);
            } catch (Error e) {
                warning ("Cannot open folder %s: %s", folder_path, e.message);
            }
        }
    }
}
