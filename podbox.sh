#!/bin/bash

set -e

function show_ussage_message() {
  echo "Usage: "
  echo "  podbox command"
  echo "Available Commands:"
  echo "  create Name [OPTIONS]                   Create new container"
  echo "    Available Options:"
	echo "      --gui                                 Add X11 permission to run programs with gui"
	echo "      --ipc                                 Add ipc permission. Should be used with gui option"
	echo "      --audio                               Add PulseAudio permission to play audio"
	echo "      --net                                 Add network permission"
	echo "      --security on|off|unconfined          Enable/Disable SELinux permissions for container"
	echo "      --map-user                            Map host user to guest user"
	echo "      --volume /host/path[:/cont/path]      Mount path to container"
	echo "  bash Name [--root]                      Run shell inside container"
	echo "  exec Name command                       Run command inside container"
	echo "  remove Name                             Remove container"
	echo "  volume add Name /host/path [OPTIONS]    Add volume to container"
  echo "    Available Options:"
	echo "      --to [/container/path]                Set container path"
	echo "      --type ro|rsync                       Moutn type"
	echo "  volume rm Name /host/path               Remove volume from container"
	echo "  read-only Name on|off                   Set container as read-only. All changes in container file system will be cleared on stop"
	echo "  net Name on|off                         Add/Remove network permission"
	echo "  ipc Name on|off                         Add/Remove ipc permission. Should be used with gui option"
	echo "  audio Name on|off                       Add/Remove PulseAudio permission to play audio"
	echo "  net Name on|off                         Add/Remove network permission"
	echo "  security Name on|off|unconfined         Enable/Disable SELinux permissions for container"
	echo "  map-user Name on|off                    Map/Unmap host user to guest user"
	echo "  desktop create Name AppCmd AppName      Create desktop entry for container program"
  echo "    Available Options:"
	echo "      --icon /path/to/icon                  Set icon for desktop entry"
	echo "      --cont_icon /path/to/icon             Set icon from container for desktop entry"
	echo "      --categories /path/to/icon            Set categories for desktop entry"
	echo "  desktop rm Name AppCmd                  Remove desktop entry"
}

container_prefix=""
declare -A container_volumes
declare -A container_params
declare -A container_desktop_entries

function read_settings_file() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"
  mkdir -p "$(dirname "$config_file")"

  local line_list=()
  set +e
  readarray -d $'\n' -t line_list < "$config_file"
  set -e

  local parse_block=""
  for line in "${line_list[@]}"; do
    if [[ ${line:0:1} == "#" ]]; then
      parse_block="$line"
    elif [ "$parse_block" = "#volumes" ]; then
      container_volumes["${line}"]="${line}"
    elif [ "$parse_block" = "#params" ]; then
      local kv=(${line//=/ })
      container_params["${kv[0]}"]=${kv[1]}
    elif [ "$parse_block" = "#desktop" ]; then
      container_desktop_entries["${line}"]="${line}"
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

  echo '#desktop' >>"$config_file"
  for entry in "${container_desktop_entries[@]}"; do
    echo "$entry" >>"$config_file"
  done
  echo '#end' >>"$config_file"
}

function delete_settings_file() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"

  rm -f "$config_file"
}

function checkIfNoBoxExist() {
  local box_name="$1"

  set +e
  podman container inspect "$box_name" &> /dev/null
  local status_c=$?
  podman image exists "$box_name"
  local status_i=$?
  set -e

  if [ $status_c -eq 0 ] || [ $status_i -eq 0 ]; then
    echo "Error: box with name $box_name exsist"
    exit 1
  fi
}

function checkIfBoxExist() {
  local box_name="$1"

  set +e
  podman container inspect "$box_name" &> /dev/null
  local status_c=$?
  podman image exists "$box_name"
  local status_i=$?
  set -e

  if [ $status_c -ne 0 ] && [ $status_i -ne 0 ]; then
    echo "Error: box with name $box_name not found"
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
        if [ "$2" = "on" ] || [ "$2" = "off" ] || [ "$2" = "unconfined" ]; then
          container_params["security"]="$2"
        else
          echo "Error: Illegal value $2"
          show_ussage_message
          exit 1
        fi
        shift;;
      "--volume")
        container_volumes["$2"]="$2"
        shift;;
      "--home")
        container_volumes["$2:/home/user"]="$2:/home/user"
        shift;;
      *)
        echo "Error: unknown flag: $1"
        show_ussage_message
        exit 1;;
    esac
    shift
  done
}

function gen_podman_options() {
  local box_name="$1"
  local container_name="$container_prefix$box_name"

  podman_options=""
  podman_options+=" --name $container_name"
  podman_options+=" --hostname $box_name"
  podman_options+=" --interactive"
  podman_options+=" --tty"
  podman_options+=" --env LANG=C.UTF-8"
  podman_options+=" --env TERM=${TERM}"

  if [ "${container_params["read-only"]}" = "on" ]; then
    podman_options+=" --rm"
  fi

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

  checkIfNoBoxExist "$box_name"

  local user_id=$(id -ru)
  gen_podman_options "$box_name"

  local home_mount=""
  for volume in "${container_volumes[@]}"; do
    if [[ $volume == *":/home/user" ]]; then
      home_mount="${volume}"
      echo 'home_cr'
    fi

    echo "$volume"
  done

  local container_name="$container_prefix$box_name"

  if [ "${home_mount}" != "" ]; then
    podman create --interactive --tty --name "$container_name" --user root --volume "${home_mount}" --security-opt label=disable registry.fedoraproject.org/fedora:30
    podman start "$container_name"
    podman exec --user root "$container_name" useradd --uid "$user_id" user
    podman exec --user root "$container_name" cp -r /etc/skel/. /home/user
  else
    podman create --interactive --tty --name "$container_name" --user root registry.fedoraproject.org/fedora:30
    podman start "$container_name"
    podman exec --user root "$container_name" useradd --uid "$user_id" user
  fi

  podman stop "$container_name"
  podman commit "$container_name" "$container_name"
  podman rm "$container_name"
  eval "podman create $podman_options --user user $container_name"
  podman start "$container_name"
  podman exec --user root "$container_name" chown -R user:user /home/user

  write_settings_file "$box_name"
}

function override_container_params() {
  local box_name="$1"

  local container_name="$container_prefix$box_name"
  gen_podman_options "$box_name"

  set +e
  podman stop --timeout 2 "$container_name" 2> /dev/null
  podman commit "$container_name" "$container_name" 2> /dev/null
  podman rm "$container_name" 2> /dev/null
  set -e

  eval "podman create $podman_options --user user $container_name"
}

function action_remove() {
  local box_name="$1"
  shift

  if [ "$#" -ne "0" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  desktop_remove_all "$box_name"

  delete_settings_file "$box_name"

  local container_name="$container_prefix$box_name"

  set +e
  podman stop --timeout 2 "$container_name" 2> /dev/null
  podman rm "$container_name" 2> /dev/null
  podman rmi "$container_name" 2> /dev/null
  set -e
}

function exec_in_container() {
  local box_name="$1"
  shift
  local userName="$1"
  shift
  local command="$1"
  shift

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"
  gen_podman_options "$box_name"

  local container_name="$container_prefix$box_name"

  set +e
  eval "podman create $podman_options --user user $container_name" 2> /dev/null
  set -e

  podman start "$container_name"
  podman exec --interactive --tty --user "$userName" "$container_name" "$command" "$@"
}

function action_bash() {
  local box_name="$1"
  shift

  local userName="user"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--root")
        userName="root";;
      *)
        echo "Error: unknown flag: $1"
        show_ussage_message
        exit 1;;
    esac
    shift
  done

  exec_in_container "$box_name" "$userName" "/bin/bash"
}

function action_exec() {
  local box_name="$1"
  shift

  local userName="user"
  if [ "$1" = "--root" ]; then
    userName="root"
    shift;
  fi

  exec_in_container "$box_name" "$userName" "$@"
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

  checkIfBoxExist "$box_name"
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

  checkIfBoxExist "$box_name"
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
    *)
      echo "Unknown command $action"
      show_ussage_message ;;
  esac
}

function action_read_only() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["read-only"]="$value"
  else
    echo "Error: Illegal value $value"
    show_ussage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_net() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["net"]="$value"
  else
    echo "Error: Illegal value $value"
    show_ussage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_ipc() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["ipc"]="$value"
  else
    echo "Error: Illegal value $value"
    show_ussage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_gui() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["gui"]="$value"
  else
    echo "Error: Illegal value $value"
    show_ussage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_audio() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["audio"]="$value"
  else
    echo "Error: Illegal value $value"
    show_ussage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_map_user() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["map-user"]="$value"
  else
    echo "Error: Illegal value $value"
    show_ussage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_security() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ] || [ "$value" = "unconfined" ]; then
    container_params["security"]="$value"
  else
    echo "Error: Illegal value $value"
    show_ussage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_desktop_add() {
  local box_name="$1"; shift
  local bin_name="$1"; shift
  local icon_title="$1"; shift

  local categories="Utility"
  local icon_file=""
  local isContainerIcon=false

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--icon")
        icon_file="$2"
        shift;;
      "--cont_icon")
        isContainerIcon=true
        icon_file="$2"
        shift;;
      "--categories")
        categories="$2"
        shift;;
      *)
        echo "Error: unknown flag: $1"
        show_ussage_message
        exit 1;;
    esac
    shift
  done

  if [ $isContainerIcon = true ]; then
    podman cp "$box_name:$icon_file" ~/.icons/
    icon_file="$HOME/.icons/$(basename "$icon_file")"
  fi

  desktop="[Desktop Entry]
Version=1.0
Name=$icon_title
GenericName=$icon_title
Exec=podbox exec $box_name $bin_name
Icon=$icon_file
Terminal=false
Type=Application
StartupNotify=true
Categories=$categories

X-Desktop-File-Install-Version=0.23"

  rm -f "/home/admin/.local/share/applications/$box_name-$bin_name.desktop"
  echo "$desktop" >> "/home/admin/.local/share/applications/$box_name-$bin_name.desktop"

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  container_desktop_entries["$box_name-$bin_name"]="$box_name-$bin_name"

  write_settings_file "$box_name"
}

function action_desktop_remove() {
  local box_name="$1"
  local bin_name="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  rm -f "/home/admin/.local/share/applications/$box_name-$bin_name.desktop"

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  unset container_desktop_entries["$box_name-$bin_name"]

  write_settings_file "$box_name"
}

function desktop_remove_all() {
  local box_name="$1"

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  for entry in "${container_desktop_entries[@]}"; do
    rm -f "/home/admin/.local/share/applications/$entry.desktop"
  done
}

function action_desktop() {
  local action="$1"
  shift

  case "$action" in
    "create") action_desktop_add "$@" ;;
    "rm") action_desktop_remove "$@" ;;
    *)
      echo "Unknown command $action"
      show_ussage_message ;;
  esac
}

# Will be removed in future release and moved to sepparate script

function action_install_tar() {
  if [ "$#" -lt 3 ]; then
    echo "Error: Illegal count of arguments"
    show_ussage_message
    exit 1
  fi

  local box_name="$1"; shift
  local app_url="$1"; shift
  local app_name="$1"; shift

  local tar_params="-xz -C /opt/$app_name"
  local bin_path=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--strip")
        tar_params+=" --strip-components=1";;
      "--bin")
        bin_path="$2"
        shift;;
      *)
        echo "Error: unknown flag: $1"
        show_ussage_message
        exit 1;;
    esac
    shift
  done

  exec_in_container "$box_name" "root" "dnf" "install" "-y" "wget"
  exec_in_container "$box_name" "root" "mkdir" "-p" "/opt/$app_name"

  local wgetcmd="wget -c $app_url -O - | tar $tar_params"
  exec_in_container "$box_name" "root" "bash" "-c" "${wgetcmd}"

  if [ "$bin_path" != "" ]; then
    exec_in_container "$box_name" "root" "cp" "-s" "/opt/$app_name/$bin_path" "/usr/bin/$(basename "$bin_path")"
  fi
}

function action_install() {
  local action="$1"
  shift

  case "$action" in
    "tar") action_install_tar "$@" ;;
    *)
      echo "Unknown command $action"
      show_ussage_message ;;
  esac
}

function entry() {
  if [ "$#" -eq "0" ]; then
    show_ussage_message
    exit 1
  fi

  local action="$1"
  shift

  case "$action" in
    "create") action_create "$@" ;;
    "bash") action_bash "$@" ;;
    "exec") action_exec "$@" ;;
    "remove") action_remove "$@" ;;
    "volume") action_volume "$@" ;;
    "read-only") action_read_only "$@" ;;
    "net") action_net "$@" ;;
    "ipc") action_ipc "$@" ;;
    "gui") action_gui "$@" ;;
    "audio") action_audio "$@" ;;
    "map-user") action_map_user "$@" ;;
    "security") action_security "$@" ;;
    "desktop") action_desktop "$@" ;;
    "install") action_install "$@" ;;
    *)
      echo "Unknown command $action"
      show_ussage_message ;;
  esac
}

entry "$@"
