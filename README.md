# Podman sandbox for GUI applications 

```
Usage: podbox.sh command
  container create containerName [OPTIONS]    Create container
    Options:
      --map-user                              Map host user to user with same uid inside the container
      --audio                                 Expose pulseaudio sound server inside the container
      --x11                                   Expose X11 socket inside the container
      --volume path[:mount[:ro|rslave]]       Bind mount a volume into the container
      --ipc                                   IPC namespace to use
  container delete containerName             Delete container
  container bash containerName [--root]      Enter container bash
  container exec containerName command       Run command inside container
  sandbox create containerName sandboxName   Create immutable sandbox from sandbox
  sandbox bash sandboxName [OPTIONS]         Enter sandbox bash
    Options:
      --map-user                              Map host user to user with same uid inside the container
      --audio                                 Expose pulseaudio sound server inside the container
      --x11                                   Expose X11 socket inside the container
      --volume path[:mount[:ro|rslave]]       Bind mount a volume into the container
      --ipc                                   IPC namespace to use
      --root                                  Execute as root
  sandbox exec sandboxName command [OPTIONS] Run command inside sandbox
    Options:
      --map-user                              Map host user to user with same uid inside the container
      --audio                                 Expose pulseaudio sound server inside the container
      --x11                                   Expose X11 socket inside the container
      --volume path[:mount[:ro|rslave]]       Bind mount a volume into the container
      --ipc                                   IPC namespace to use
      --root                                  Execute as root
  sandbox delete sandboxName                 Delete sandbox
```
