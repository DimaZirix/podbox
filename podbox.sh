#!/bin/bash

set -e

function show_ussage_message() {
  echo "error"
}

declare -A container_volumes
declare -A container_params

function read_settings_file() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"
  mkdir -p "$(dirname "$config_file")"

  local line_list=()
  readarray -d $'\n' -t line_list < "$config_file"

  local parse_block=""
  for line in "${line_list[@]}"; do
    if [[ ${line:0:1} == "#" ]]; then
      parse_block="$line"
    elif [ "$parse_block" = "#volumes" ]; then
      container_volumes["${line}"]="${line}"
    elif [ "$parse_block" = "#params" ]; then
      local kv=(${line//=/ })
      container_params["${kv[0]}"]=${kv[1]}
    fi
  done
}

function write_settings_file() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"
  mkdir -p "$(dirname "$config_file")"

  echo '#volumes' >"$config_file"
  for volume in "${container_volumes[@]}"; do
    echo "$volume" >>"$config_file"
  done
  echo '#end' >>"$config_file"

  echo '#params' >>"$config_file"
  for key in "${!container_params[@]}"; do
    echo "${key}=${container_params[$key]}" >>"$config_file"
  done
  echo '#end' >>"$config_file"
}

function delete_settings_file() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"

  rm -f "$config_file"
}

function checkNoBoxExsist() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"

  if [ -f "$config_file" ]; then
    echo "Error: box with name $box_name exsist"
    show_ussage_message
    exit 1
  fi
}

function checkBoxExsist() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"

  if [ ! -f "$config_file" ]; then
    echo "Error: box with name $box_name not found"
    show_ussage_message
    exit 1
  fi
}

function parse_config_params() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--gui"|"--x11"|"--X11") container_params["gui"]="on";;
      "--audio") container_params["audio"]="on";;
      "--ipc") container_params["ipc"]="on";;
      "--map-user") container_params["map-user"]="on";;
      "--net") container_params["net"]="on";;
      "--security")
        container_params["security"]="$2"
        shift;;
      "--volume")
        container_volumes["$2"]=("$2")
        shift;;
      -*)
        echo "Error: unknown flag: $1"
        show_ussage_message
        exit 1;;
      *)break;;
    esac
    shift
  done

  parse_params=$@
}

function gen_podman_options() {
  local box_name="$1"
  local container_name="podbox_$box_name"

  podman_options=""
  podman_options+=" --name $container_name"
  podman_options+=" --hostname $box_name"
  podman_options+=" --interactive"
  podman_options+=" --tty"
  podman_options+=" --env LANG=C.UTF-8"
  podman_options+=" --env TERM=${TERM}"

  if [ "${container_params["net"]}" = "on" ]; then
    podman_options+=" --network slirp4netns"
  else
    podman_options+=" --network none"
  fi

  if [ "${container_params["ipc"]}" = "on" ]; then
    podman_options+=" --ipc host"
  fi

  # X11 Mapping
  if [ "${container_params["gui"]}" = "on" ]; then
    podman_options+=" --env "DISPLAY=${DISPLAY}""
    podman_options+=" --volume /tmp/.X11-unix:/tmp/.X11-unix"
    podman_options+=" --device /dev/dri"

    container_params["map-user"]="on"
    if [ "${container_params["security"]}" = "" ]; then
      container_params["security"]="off"
    fi
  fi

  # PulseAudio
  if [ "${container_params["audio"]}" = "on" ]; then
    podman_options+=" --volume /etc/machine-id:/etc/machine-id:ro"
    podman_options+=" --env XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    podman_options+=" --volume ${XDG_RUNTIME_DIR}/pulse/native:${XDG_RUNTIME_DIR}/pulse/native"

    container_params["map-user"]="on"
    if [ "${container_params["security"]}" = "" ]; then
      container_params["security"]="off"
    fi
  fi

  # Current user mapping
  if [ "${container_params["map-user"]}" = "on" ]; then
    local id_real=$(id -ru)
    local uid_count=65536
    local minus_uid=$((uid_count - id_real))
    local plus_uid=$((id_real + 1))
    podman_options+=" --uidmap ${id_real}:0:1"
    podman_options+=" --uidmap 0:1:${id_real}"
    podman_options+=" --uidmap ${plus_uid}:${plus_uid}:${minus_uid}"
  fi

  if [ "${container_params["security"]}" = "off" ]; then
    podman_options+=" --security-opt label=disable"
  elif [ "${container_params["security"]}" = "unconfined" ]; then
    podman_options+=" --security-opt label=disable"
    podman_options+=" --security-opt seccomp=unconfined"
  fi

  for volume in "${container_volumes[@]}"; do
    podman_options+=" --volume ${volume}"
  done
}

function action_create() {
  local box_name="$1"
  shift

  parse_config_params "$@"
  set -- "$parse_params"

  if [ "$#" -ne "1" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkNoBoxExsist "$box_name"

  local user_id=$(id -ru)
  gen_podman_options "$box_name"

  local container_name="podbox_$box_name"
  podman create --interactive --tty --name "$container_name" --user root registry.fedoraproject.org/fedora:30
  podman start "$container_name"
  podman exec --user root "$container_name" useradd --uid "$user_id" user
  podman stop "$container_name"
  podman commit "$container_name" "$container_name"
  podman rm "$container_name"
  eval "podman create $podman_options --user user $container_name"

  write_settings_file "$box_name"
}

function action_remove() {
  local box_name="$1"
  shift

  if [ "$#" -ne "0" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  delete_settings_file "$box_name"

  local container_name="podbox_$box_name"
  podman rm "$container_name"
}

function override_container_params() {
  local box_name="$1"

  local container_name="podbox_$box_name"
  gen_podman_options "$box_name"

  set +e
  podman stop --timeout 2 "$container_name"
  set -e

  podman commit "$container_name" "$container_name"
  podman rm "$container_name"
  eval "podman create $podman_options --user user $container_name"
}

function action_volume_add() {
  local box_name="$1"
  shift
  local host_path="$1"
  shift
  local container_point="$host_path"
  local mount_type=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--to")
        container_point="$2"
        shift;;
      "--type")
        mount_type=":$2"
        shift;;
      *)
        echo "Error: unknown flag: $1"
        show_ussage_message
        exit 1;;
    esac
    shift
  done

  local mount_value="$host_path:$container_point$mount_type"

  checkBoxExsist "$box_name"
  read_settings_file "$box_name"

  container_volumes["${mount_value}"]="${mount_value}"

  override_container_params "$box_name"

  write_settings_file "$box_name"
}

function action_volume_remove() {
  local box_name="$1"
  local host_path="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkBoxExsist "$box_name"
  read_settings_file "$box_name"

  for volume in "${container_volumes[@]}"; do
    if [[ $volume == "${host_path}:"* ]]; then
      unset container_volumes["${volume}"]
    fi
  done

  override_container_params "$box_name"

  write_settings_file "$box_name"
}

function action_volume() {
  local action="$1"
  shift

  case "$action" in
    "add") action_volume_add "$@" ;;
    "rm") action_volume_remove "$@" ;;
    *) show_ussage_message ;;
  esac
}

function entry() {
  local action="$1"
  shift

  case "$action" in
    "create") action_create "$@" ;;
    "rm") action_remove "$@" ;;
    "volume") action_volume "$@" ;;
    *) show_ussage_message ;;
  esac
}

entry "$@"
