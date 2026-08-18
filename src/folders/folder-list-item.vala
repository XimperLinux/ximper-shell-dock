namespace XimperShellDock {

    private class FolderListItem : Object {
        public File file;
        public FileInfo info;

        public FolderListItem (File file, FileInfo info) {
            this.file = file;
            this.info = info;
        }
    }
}
