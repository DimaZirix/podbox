Name:    podbox
Version: 1
Release: 1
Summary: podbox

Source0: podbox.sh

License: MIT

Requires(post): info
Requires(preun): info

Requires: podman

BuildArch: noarch

%description
Podman sandbox for GUI applications

%install
mkdir -p %{buildroot}/%{_bindir}
install -p -m 755 %{SOURCE0} %{buildroot}/%{_bindir}

%post
if [ -f "/usr/bin/podbox" ]; then
 unlink /usr/bin/podbox
fi
cp -s /usr/bin/podbox.sh /usr/bin/podbox

%preun
if [ -f "/usr/bin/podbox" ]; then
  unlink /usr/bin/podbox
fi

%files
%{_bindir}/podbox.sh

%changelog
