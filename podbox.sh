#!/bin/bash

set -e

function show_ussage_message() {
  echo "Usage: podbox.sh command"
  echo "  container create containerName [OPTIONS]    Create container"
  echo "    Options:"
	echo "      --map-user                              Map host user to user with same uid inside the container"
	echo "      --audio                                 Expose pulseaudio sound server inside the container"
	echo "      --x11                                   Expose X11 socket inside the container"
	echo "      --volume path[:mount[:ro|rslave]]       Bind mount a volume into the container"
	echo "      --ipc                                   IPC namespace to use"
  echo "  container delete containerName             Delete container"
  echo "  container bash containerName [--root]      Enter container bash"
  echo "  container exec containerName command       Run command inside container"
  echo "  sandbox create containerName sandboxName   Create immutable sandbox from sandbox"
  echo "  sandbox bash sandboxName [OPTIONS]         Enter sandbox bash"
  echo "    Options:"
	echo "      --map-user                              Map host user to user with same uid inside the container"
	echo "      --audio                                 Expose pulseaudio sound server inside the container"
	echo "      --x11                                   Expose X11 socket inside the container"
	echo "      --volume path[:mount[:ro|rslave]]       Bind mount a volume into the container"
	echo "      --ipc                                   IPC namespace to use"
	echo "      --root                                  Execute as root"
  echo "  sandbox exec sandboxName command [OPTIONS] Run command inside sandbox"
  echo "    Options:"
	echo "      --map-user                              Map host user to user with same uid inside the container"
	echo "      --audio                                 Expose pulseaudio sound server inside the container"
	echo "      --x11                                   Expose X11 socket inside the container"
	echo "      --volume path[:mount[:ro|rslave]]       Bind mount a volume into the container"
	echo "      --ipc                                   IPC namespace to use"
	echo "      --root                                  Execute as root"
  echo "  sandbox delete sandboxName                 Delete sandbox"
}

function container_create() {
  local isX11=false;
  local isAudio=false;
  local isIpc=false;
  local isUserMapping=false;
  local volumes=""
  local params=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--X11") isX11=true;;
      "--audio") isAudio=true;;
      "--ipc") isIpc=true;;
      "--user-mapping") isUserMapping=true;;
      "--volume")
        volumes+=" --volume $2"
        shift;;
      -*)
        echo "Error: unknown flag: $1"
        echo ""
        show_ussage_message
        exit 1;;
      *)params+=("$1");;
    esac
    shift
  done
  set -- "${params[@]}"

  if [ "$#" -lt "1" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  local name="$1"; shift;
  local options=$(get_options "$name" "$isX11" "$isAudio" "$isIpc" "$isUserMapping" "$volumes")

  eval "podman create $options --user root registry.fedoraproject.org/fedora:30"
  podman start "$name"

  local user_id=$(id -ru)
  podman exec --user root "$name" useradd --uid "$user_id" user
}

function container_delete() {
  if [ "$#" -ne "1" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  set +e

  local name="$1"
  eval "podman stop $name --timeout 1 2> /dev/null"
  eval "podman rm $name"
}

function container_bash() {
  local userName="user";

  local params=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--root") userName="root";;
      -*)
        echo "Error: unknown flag: $1"
        echo ""
        show_ussage_message
        exit 1;;
      *)params+=("$1");;
    esac
    shift
  done
  set -- "${params[@]}"

  if [ "$#" -ne "1" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  local name="$1"
  podman start "$name"
  podman exec --interactive --tty --user $userName "$name" /bin/bash
}

function container_exec() {
  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  local name="$1"
  local command="$2"
  podman start "$name"
  podman exec --interactive --tty --user user "$name" "$command"
}

function get_options() {
  local name="$1";
  local isX11="$2";
  local isAudio="$3";
  local isIpc="$4";
  local isUserMapping="$5";
  local isDisableSecurity=false
  local volumes="$6"

  local options=""
  options+=" --name $name"
  options+=" --hostname $name"
  options+=" --interactive"
  options+=" --tty"
  options+=" --env LANG=C.UTF-8"
  options+=" --env TERM=${TERM}"

  if [ "$isIpc" = true ]; then
    options+=" --ipc host"
  fi

  # X11 Mapping
  if [ "$isX11" = true ]; then
    options+=" --env "DISPLAY=${DISPLAY}""
    options+=" --volume /tmp/.X11-unix:/tmp/.X11-unix"
    options+=" --device /dev/dri"

    isUserMapping=true
    isDisableSecurity=true
  fi

  # PulseAudio
  if [ "$isAudio" = true ]; then
    options+=" --volume /etc/machine-id:/etc/machine-id:ro"
    options+=" --env XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    options+=" --volume ${XDG_RUNTIME_DIR}/pulse/native:${XDG_RUNTIME_DIR}/pulse/native"

    isUserMapping=true
    isDisableSecurity=true
  fi

  # Current user mapping
  if [ "$isUserMapping" = true ]; then
    local id_real=$(id -ru)
    local uid_count=65536
    local minus_uid=$((uid_count - id_real))
    local plus_uid=$((id_real + 1))
    options+=" --uidmap ${id_real}:0:1"
    options+=" --uidmap 0:1:${id_real}"
    options+=" --uidmap ${plus_uid}:${plus_uid}:${minus_uid}"
  fi

  if [ "$isDisableSecurity" = true ]; then
    options+=" --security-opt label=disable"
  fi

  echo "${options[@]}" "${volumes[@]}"
}

function sandbox_create() {
  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  local container="$1"
  local image="sandbox_$2"
  podman commit "$container" "$image"
}

function sandbox_bash() {
  local isX11=false;
  local isAudio=false;
  local isIpc=false;
  local isUserMapping=false;
  local volumes=""
  local params=()
  local userName="user"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--root") userName="root";;
      "--X11") isX11=true;;
      "--audio") isAudio=true;;
      "--ipc") isIpc=true;;
      "--user-mapping") isUserMapping=true;;
      "--volume")
        volumes+=" --volume $2"
        shift;;
      -*)
        echo "Error: unknown flag: $1"
        echo ""
        show_ussage_message
        exit 1;;
      *)params+=("$1");;
    esac
    shift
  done
  set -- "${params[@]}"

  if [ "$#" -lt "1" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  local name="sandbox_$1";
  local options=$(get_options "$name" "$isX11" "$isAudio" "$isIpc" "$isUserMapping" "$volumes")

  eval "podman run $options --rm --user $userName localhost/$name /bin/bash"
}

function sandbox_exec() {
  local isX11=false;
  local isAudio=false;
  local isIpc=false;
  local isUserMapping=false;
  local volumes=""
  local params=()
  local userName="user"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--root") userName="root";;
      "--X11") isX11=true;;
      "--audio") isAudio=true;;
      "--ipc") isIpc=true;;
      "--user-mapping") isUserMapping=true;;
      "--volume")
        volumes+=" --volume $2"
        shift;;
      -*)
        echo "Error: unknown flag: $1"
        echo ""
        show_ussage_message
        exit 1;;
      *)params+=("$1");;
    esac
    shift
  done
  set -- "${params[@]}"

  if [ "$#" -lt "1" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  local name="sandbox_$1";
  local command="$2";
  local options=$(get_options "$name" "$isX11" "$isAudio" "$isIpc" "$isUserMapping" "$volumes")

  eval "podman run $options --rm --user $userName localhost/$name $command"
}

function sandbox_delete() {
  if [ "$#" -ne "1" ]; then
    echo "Error: Illegal count of arguments"
    echo ""
    show_ussage_message
    exit 1
  fi

  set +e

  local name="sandbox_$1"
  eval "podman stop $name --timeout 1 2> /dev/null"
  eval "podman rmi $name"
}

function start() {
  if [ "$#" -lt "2" ]; then
    show_ussage_message
    exit 1
  fi

  local command="$1 $2"; shift; shift;

  case "$command" in
    "container create") container_create "$@";;
    "container delete") container_delete "$@";;
    "container bash") container_bash "$@";;
    "container exec") container_exec "$@";;
    "sandbox create") sandbox_create "$@";;
    "sandbox bash") sandbox_bash "$@";;
    "sandbox exec") sandbox_exec "$@";;
    "sandbox delete") sandbox_delete "$@";;
    *) show_ussage_message;;
  esac
}

start "$@";
