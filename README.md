# Podman sandbox for GUI applications 

#### Example

#### Tor browser inside podman container

```
$ podbox.sh create torbrowser --gui --net --ipc
$ podbox.sh exec torbrowser --root dnf install torbrowser-launcher libXt dbus-glib gtk3 -y
$ podbox.sh read-only on torbrowser
$ exec torbrowser --root cp -s /home/user/.local/share/torbrowser/tbb/x86_64/tor-browser_en-US/Browser/start-tor-browser /usr/bin/torbrowser
$ podbox.sh exec torbrowser torbrowser

```

```
Usage: 
  podbox command
Available Commands:
  create Name [OPTIONS]                   Create new container
    Available Options:
      --gui                                 Add X11 permission to run programs with gui
      --ipc                                 Add ipc permission. Should be used with gui option
      --audio                               Add PulseAudio permission to play audio
      --net                                 Add network permission
      --security on|off|unconfined          Enable/Disable SELinux permissions for container
      --map-user                            Map host user to guest user
      --volume /host/path[:/cont/path]      Mount path to container
  bash Name [--root]                      Run shell inside container
  exec Name command                       Run command inside container
  remove Name                             Remove container
  volume add Name /host/path [OPTIONS]    Add volume to container
    Available Options:
      --to [/container/path]                Set container path
      --type ro|rsync                       Moutn type
  volume rm Name /host/path               Remove volume from container
  read-only on|off Name                   Set container as real-only. All data will be lost after stop
  net on|off Name                         Add/Remove network permission
  ipc on|off Name                         Add/Remove ipc permission. Should be used with gui option
  audio on|off Name                       Add/Remove PulseAudio permission to play audio
  net on|off Name                         Add/Remove network permission
  security on|off|unconfined Name         Enable/Disable SELinux permissions for container
  map-user on|off Name                    Map/Unmap host user to guest user
```
