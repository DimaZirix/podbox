#!/bin/bash

set -e

function show_ussage_message() {
  echo "Usage: podbox.sh command [OPTIONS]"
  echo "  container create containerName            Create container"
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
      "--share")
        volumes+=" --volume $2:$2"
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
    echo "Error: Illegal count of operations"
    show_ussage_message
    exit 1
  fi

  local name="$1"; shift;
  local options=$(get_options "$isX11" "$isAudio" "$isIpc" "$isUserMapping" "$volumes")

  echo "$options"

  eval "podman create $options --name $name --hostname $name registry.fedoraproject.org/fedora:30"
  podman start "$name"

  local user_id=$(id -ru)
  podman exec --user root "$name" useradd --uid "$user_id" user
}

function container_delete() {
  if [ "$#" -ne "1" ]; then
    echo "Error: Illegal count of operations"
    show_ussage_message
    exit 1
  fi

  set +e

  local name="$1"
  eval "podman stop $name --timeout 1"
  eval "podman rm $name"
}

function container_bash() {
  if [ "$#" -ne "1" ]; then
    echo "Error: Illegal count of operations"
    show_ussage_message
    exit 1
  fi

  local name="$1"
  podman start "$name"
  podman exec --interactive --tty --user user "$name" /bin/bash
}

function container_exec() {
  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of operations"
    show_ussage_message
    exit 1
  fi

  local name="$1"
  local command="$2"
  podman start "$name"
  podman exec --interactive --tty --user user "$name" "$command"
}

function get_options() {
  local isX11="$1";
  local isAudio="$2";
  local isIpc="$3";
  local isUserMapping="$4";
  local isDisableSecurity=false
  local volumes="$5"

  local options=""
  options+=" --interactive"
  options+=" --user root:root"
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
    *) show_ussage_message;;
  esac
}

start "$@";