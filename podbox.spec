Name:    podbox
Version: 1
Release: 0
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
set +e
cp -s /usr/bin/podbox.sh /usr/bin/podbox

%preun
set +e
unlink /usr/bin/podbox

%files
%{_bindir}/podbox.sh

%changelog
