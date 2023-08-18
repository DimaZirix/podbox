# Container sandbox for GUI applications 
Script uses podman to create and run an aplications inside a container

#### Installing

```shell script
sudo dnf copr enable zirix/Podbox
sudo dnf install podbox
```
or download and use podbox.sh

#### Examples

```shell script
# create a container with a "ContainerName" name
# run as user, no root/sudo required
podbox create ContainerName --gui --net --ipc --audio

# then run bash
podbox bash ContainerName
# (use --root option to run bash as root)

# run a command inside the container
podbox exec ContainerName Command
# (use --root option to run command as root)

# Create a desktop icon for the command inside the container
podbox desktop create ContainerName Command 'Desktop icon title'
# (use --icon /path/to/icon/ option or --cont_icon /path/to/icon/inside/container)

# add(share) path to the a container
podbox volume add ContainerName /path
```

#### Install Firefox inside a container

```shell script
podbox create firefox --gui --net --ipc --audio
podbox exec firefox --root dnf install firefox libXt dbus-glib gtk3 pulseaudio-libs -y
podbox desktop create firefox firefox 'Firefox Inside Podbox' --icon firefox

Now you can run browser with desktop icon or:
podbox exec firefox firefox 

```

#### Install Tor browser inside a container

```shell script
podbox create torbrowser --gui --net --ipc --audio
podbox exec torbrowser --root dnf install torbrowser-launcher libXt dbus-glib gtk3 pulseaudio-libs -y
podbox exec torbrowser torbrowser-launcher
podbox exec torbrowser --root cp -s /home/user/.local/share/torbrowser/tbb/x86_64/tor-browser_en-US/Browser/start-tor-browser /usr/bin/torbrowser
podbox read-only torbrowser on
podbox desktop create torbrowser torbrowser 'TorBrowser in PodBox' --icon torbrowser

Now you can run browser with desktop icon or:
podbox exec torbrowser torbrowser

```

```
Usage: 
  podbox command
Available Commands:
  create Name [OPTIONS]                   Create a new container
    Available Options:
      --gui                                 Add X11 permission to run GUI programs
      --ipc                                 Add ipc permission. Should be used with GUI option
      --audio                               Add PulseAudio permission to play audio
      --net                                 Add network permission
      --security on|off|unconfined          Enable/Disable SELinux permissions for the container
      --map-user                            Map host user to guest user
      --volume /host/path[:/cont/path]      Mount path to the container
  bash Name [--root]                      Run shell inside the container
  exec Name command                       Run command inside the container
  remove Name                             Remove the container
  volume add Name /host/path [OPTIONS]    Add volume to container
    Available Options:
      --to [/container/path]                Set container path
      --type ro|rsync                       Moutn type
  volume rm Name /host/path               Remove the volume from container
  read-only Name on|off                   Make the container read-only. All changes to the container's file system will be deleted on stop
  net Name on|off                         Add/Remove network permission
  ipc Name on|off                         Add/remove ipc permission. Should be used with GUI option
  audio Name on|off                       Add/Remove PulseAudio permission to play audio
  net Name on|off                         Add/Remove network permission
  security Name on|off|unconfined         Enable/Disable SELinux permissions for the container
  map-user Name on|off                    Map/Unmap host user to guest user
  desktop create Name AppCmd AppName      Create desktop entry for container program
    Available Options:
      --icon /path/to/icon                  Set desktop entry icon from container icon path
      --cont_icon /path/to/icon             Set desktop entry icon from host icon path
      --categories /path/to/icon            Set desktop entry categories
  desktop rm Name AppCmd                  Remove desktop entry
```
