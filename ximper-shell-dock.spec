Name: ximper-shell-dock
Version: 0.1.0
Release: eter0
Summary: Ximper Shell application dock
License: GPL-3.0-only
Group: Graphical desktop/Other
Url: https://gitlab.eterfund.ru/ximperlinux/%name

Source: %name-%version.tar

BuildRequires(pre): rpm-macros-meson
BuildRequires: meson
BuildRequires: vala
BuildRequires: pkgconfig(gtk4) >= 4.12
BuildRequires: pkgconfig(gtk4-layer-shell-0) >= 1.0
BuildRequires: pkgconfig(wayland-client)
BuildRequires: libgtk4-layer-shell-devel-vala
BuildRequires: pkgconfig(json-glib-1.0)
BuildRequires: pkgconfig(libadwaita-1) >= 1.4

%description
Wayland application dock for Ximper Shell, built with GTK4, libadwaita and
gtk4-layer-shell. Supports Hyprland and Niri.

%prep
%setup

%build
%meson
%meson_build

%install
%meson_install
%find_lang %name

%check
%meson_test

%files -f %name.lang
%doc README.md README_ru.md LICENSE
%_bindir/%name
%dir %_sysconfdir/xdg/ximper-shell/dock
%_sysconfdir/xdg/ximper-shell/dock/style.css

%changelog
* Tue Aug 11 2026 Roman Alifanov <ximper@altlinux.org> 0.1.0-eter0
- Initial build
