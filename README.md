# Container sandbox for GUI applications

Script uses podman to create and run applications inside a container.
Works on both X11 and Wayland sessions: the display sockets, xauth cookie,
D-Bus and PulseAudio are wired into the container automatically.

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
podbox create ContainerName --gui --net --audio

# then run bash
podbox bash ContainerName
# (use --root option to run bash as root)

# run a command inside the container
podbox exec ContainerName Command
# (use --root option to run command as root)

# Create a desktop icon for the command inside the container
podbox desktop create ContainerName Command 'Desktop icon title'
# (use --icon for a host icon path or themed icon name,
#  or --cont_icon for an icon path inside the container)

# add (share) a host path into the container
podbox volume add ContainerName /path
```

#### Install Firefox inside a container

```shell script
podbox create firefox --gui --net --audio
podbox exec firefox --root dnf install firefox libXt dbus-glib gtk3 pulseaudio-libs -y
podbox desktop create firefox firefox 'Firefox Inside Podbox' --icon firefox

# Now you can run the browser with the desktop icon or:
podbox exec firefox firefox
```

#### Install Tor browser inside a container

```shell script
podbox create torbrowser --gui --net --audio
podbox exec torbrowser --root dnf install torbrowser-launcher libXt dbus-glib gtk3 pulseaudio-libs -y
podbox exec torbrowser torbrowser-launcher
podbox exec torbrowser --root cp -s /home/user/.local/share/torbrowser/tbb/x86_64/tor-browser_en-US/Browser/start-tor-browser /usr/bin/torbrowser
podbox read-only torbrowser on
podbox desktop create torbrowser torbrowser 'TorBrowser in PodBox' --icon torbrowser

# Now you can run the browser with the desktop icon or:
podbox exec torbrowser torbrowser
```

#### Usage

```
Usage: 
  podbox command
Available Commands:
  create Name [OPTIONS]                   Create a new container
    Available Options:
      --gui                                 Add X11 permission to run programs with a GUI
      --ipc                                 Share the host IPC namespace (only needed by legacy X11 apps using SysV-shm MIT-SHM)
      --audio                               Add PulseAudio permission to play audio
      --net                                 Add network permission
      --security on|off|unconfined          Enable/Disable SELinux permissions for the container
      --map-user                            Map the host user to the guest user
      --volume /host/path[:/cont/path]      Mount a path into the container
      --port port:port/tcp                  Publish a container port to the host
  bash Name [--root]                      Run a shell inside the container
  exec Name command                       Run a command inside the container
  remove Name                             Remove the container
  volume add Name /host/path [OPTIONS]    Add a volume to the container
    Available Options:
      --to [/container/path]                Set the container path
      --type ro|rsync                       Mount type
  volume rm Name /host/path               Remove a volume from the container
  read-only Name on|off                   Set the container as read-only. All changes in the container's file system will be cleared on stop
  net Name on|off|host|admin              Add/Remove network permission
  ipc Name on|off                         Share the host IPC namespace on/off (only needed by legacy X11 apps using SysV-shm MIT-SHM)
  audio Name on|off                       Add/Remove PulseAudio permission to play audio
  gui Name on|off                         Add/Remove X11 permission to run programs with a GUI
  security Name on|off|unconfined         Enable/Disable SELinux permissions for the container
  map-user Name on|off                    Map/Unmap the host user to the guest user
  system Name                             Run the container as an OS
  desktop create Name AppCmd AppName      Create a desktop entry for a container program
    Available Options:
      --icon /path/to/icon                  Set an icon for the desktop entry
      --cont_icon /path/to/icon             Set an icon from the container for the desktop entry
      --categories Category1;Category2      Set categories for the desktop entry
      --wmclass WMClass                     Set StartupWMClass for the desktop entry
  desktop rm Name AppCmd                  Remove a desktop entry
  port add Name port:port/tcp             Publish a port to the host and other containers
  port rm Name port[:port/tcp]            Remove a published port
  install tar Name Url AppName [OPTIONS]  Download a tar archive and unpack it into /opt inside the container
    Available Options:
      --strip                               Strip the top-level directory from the archive
      --bin path/in/app                     Symlink a binary from the app directory into /usr/bin
```
