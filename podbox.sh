#!/bin/bash

set -e

function show_usage_message() {
  echo "Usage: "
  echo "  podbox command"
  echo "Available Commands:"
  echo "  create Name [OPTIONS]                   Create a new container"
  echo "    Available Options:"
  echo "      --gui                                 Add X11 permission to run programs with a GUI"
  echo "      --ipc                                 Share the host IPC namespace (only needed by legacy X11 apps using SysV-shm MIT-SHM)"
  echo "      --audio                               Add PulseAudio permission to play audio"
  echo "      --net                                 Add network permission"
  echo "      --security on|off|unconfined          Enable/Disable SELinux permissions for the container"
  echo "      --map-user                            Map the host user to the guest user"
  echo "      --volume /host/path[:/cont/path]      Mount a path into the container"
  echo "      --port port:port/tcp                  Publish a container port to the host"
  echo "  bash Name [--root]                      Run a shell inside the container"
  echo "  exec Name command                       Run a command inside the container"
  echo "  remove Name                             Remove the container"
  echo "  volume add Name /host/path [OPTIONS]    Add a volume to the container"
  echo "    Available Options:"
  echo "      --to [/container/path]                Set the container path"
  echo "      --type ro|rsync                       Mount type"
  echo "  volume rm Name /host/path               Remove a volume from the container"
  echo "  read-only Name on|off                   Set the container as read-only. All changes in the container's file system will be cleared on stop"
  echo "  net Name on|off|host|admin              Add/Remove network permission"
  echo "  ipc Name on|off                         Share the host IPC namespace on/off (only needed by legacy X11 apps using SysV-shm MIT-SHM)"
  echo "  audio Name on|off                       Add/Remove PulseAudio permission to play audio"
  echo "  gui Name on|off                         Add/Remove X11 permission to run programs with a GUI"
  echo "  security Name on|off|unconfined         Enable/Disable SELinux permissions for the container"
  echo "  map-user Name on|off                    Map/Unmap the host user to the guest user"
  echo "  system Name                             Run the container as an OS"
  echo "  desktop create Name AppCmd AppName      Create a desktop entry for a container program"
  echo "    Available Options:"
  echo "      --icon /path/to/icon                  Set an icon for the desktop entry"
  echo "      --cont_icon /path/to/icon             Set an icon from the container for the desktop entry"
  echo "      --categories Category1;Category2      Set categories for the desktop entry"
  echo "      --wmclass WMClass                     Set StartupWMClass for the desktop entry"
  echo "  desktop rm Name AppCmd                  Remove a desktop entry"
  echo "  port add Name port:port/tcp             Publish a port to the host and other containers"
  echo "  port rm Name port[:port/tcp]            Remove a published port"
  echo "  install tar Name Url AppName [OPTIONS]  Download a tar archive and unpack it into /opt inside the container"
  echo "    Available Options:"
  echo "      --strip                               Strip the top-level directory from the archive"
  echo "      --bin path/in/app                     Symlink a binary from the app directory into /usr/bin"
}

container_prefix=""
declare -A container_volumes
declare -A container_params
declare -A container_desktop_entries
declare -A container_port_list

function read_settings_file() {
  local box_name="$1"
  local config_file="$HOME/.config/podbox/$box_name"
  mkdir -p "$(dirname "$config_file")"

  local line_list=()
  if [ -f "$config_file" ]; then
    readarray -d $'\n' -t line_list < "$config_file"
  fi

  local parse_block=""
  for line in "${line_list[@]}"; do
    if [ "$line" = "" ]; then
      continue
    elif [[ ${line:0:1} == "#" ]]; then
      parse_block="$line"
    elif [ "$parse_block" = "#volumes" ]; then
      container_volumes["${line}"]="${line}"
    elif [ "$parse_block" = "#params" ]; then
      container_params["${line%%=*}"]="${line#*=}"
    elif [ "$parse_block" = "#desktop" ]; then
      container_desktop_entries["${line}"]="${line}"
    elif [ "$parse_block" = "#port" ]; then
      container_port_list["${line}"]="${line}"
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

  echo '#port' >>"$config_file"
  for entry in "${container_port_list[@]}"; do
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
    echo "Error: box named $box_name already exists"
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
    echo "Error: box named $box_name not found"
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
          show_usage_message
          exit 1
        fi
        shift;;
      "--volume")
        container_volumes["$2"]="$2"
        shift;;
      "--port")
        container_port_list["$2"]="$2"
        shift;;
      -*)
        echo "Error: unknown flag: $1"
        show_usage_message
        exit 1;;
      *)break;;
    esac
    shift
  done

  parse_params=("$@")
}

function gen_podman_options() {
  local box_name="$1"
  local container_name="$container_prefix$box_name"

  local user_id=$(id -ru)

  local session_type="$XDG_SESSION_TYPE"

  podman_options=()
  podman_options+=(--name "$container_name")
  if [ "${container_params["gui"]}" = "on" ]; then
    # GUI boxes must use the host's hostname (like Flatpak does): toolkits put
    # the hostname into WM_CLIENT_MACHINE on X11 windows, and KWin resolves it
    # via DNS. An unresolvable box hostname blocks the compositor main thread
    # in KWin::ClientMachine when short-lived windows (tooltips, popups) are
    # destroyed, freezing the whole desktop for the 2-3s DNS timeout.
    podman_options+=(--hostname "$(uname -n)")
  else
    podman_options+=(--hostname "$box_name")
  fi
  podman_options+=(--interactive)
  podman_options+=(--tty)
  podman_options+=(--userns=keep-id)
  podman_options+=(--env LANG=C.UTF-8)
  podman_options+=(--env "TERM=${TERM}")

  if [ "${container_params["read-only"]}" = "on" ]; then
    podman_options+=(--rm)
  fi

  if [ "${container_params["net"]}" = "on" ]; then
    podman_options+=(--network pasta)
  elif [ "${container_params["net"]}" = "admin" ]; then
    podman_options+=(--network pasta)
    podman_options+=(--cap-add=NET_ADMIN)
  elif [ "${container_params["net"]}" = "host" ]; then
    podman_options+=(--network host)
  elif [ "${container_params["net"]}" = "off" ]; then
    podman_options+=(--network none)
  elif [ "${container_params["net"]}" != "" ]; then
    podman_options+=(--network "${container_params["net"]}")
  fi

  if [ "${container_params["ipc"]}" = "on" ]; then
    podman_options+=(--ipc host)
  fi

  # X11 mapping
  if [ "${container_params["gui"]}" == "on" ]; then
    podman_options+=(--env DISPLAY)
    podman_options+=(--volume /tmp/.X11-unix:/tmp/.X11-unix:ro)
    podman_options+=(--device /dev/dri)

    podman_options+=(--env "XDG_SESSION_TYPE=$XDG_SESSION_TYPE")

    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
      podman_options+=(--env "XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP")
    fi

    if [ -n "$XAUTHORITY" ]; then
      podman_options+=(--volume "/run/user/$user_id/xauthmnbv:$XAUTHORITY")
      podman_options+=(--env XAUTHORITY)
    fi

    podman_options+=(--env "XDG_RUNTIME_DIR=/run/user/tmp")
#    podman_options+=(--env "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/tmp/bus")
    podman_options+=(--volume "/run/user/$user_id/bus:/run/user/tmp/bus")
#    podman_options+=(--security-opt label=disable)
#    podman_options+=(--shm-size=10g)
#    podman_options+=(--cpus 1)

    if [ "$session_type" = "wayland" ]; then
      podman_options+=(--env "WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
      podman_options+=(--volume "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/run/user/tmp/$WAYLAND_DISPLAY:ro")
      # Prefer Wayland but fall back to X11 if the toolkit's Wayland plugin is missing
      podman_options+=(--env "QT_QPA_PLATFORM=wayland;xcb")
      podman_options+=(--env "GDK_BACKEND=wayland,x11")
      podman_options+=(--env MOZ_ENABLE_WAYLAND=1)
      podman_options+=(--env ELECTRON_OZONE_PLATFORM_HINT=auto)
    fi

    container_params["map-user"]="on"
    if [ "${container_params["security"]}" = "" ]; then
      container_params["security"]="off"
    fi
  fi

  # PulseAudio
  if [ "${container_params["audio"]}" = "on" ]; then
    podman_options+=(--volume /etc/machine-id:/etc/machine-id:ro)
    podman_options+=(--volume "${XDG_RUNTIME_DIR}/pulse/native:/run/user/tmp/pulse/native:ro")

    container_params["map-user"]="on"
    if [ "${container_params["security"]}" = "" ]; then
      container_params["security"]="off"
    fi
  fi

  if [ "${container_params["security"]}" = "off" ]; then
    podman_options+=(--security-opt=no-new-privileges)
  elif [ "${container_params["security"]}" = "unconfined" ]; then
    podman_options+=(--cap-drop=ALL --security-opt=no-new-privileges)
    podman_options+=(--security-opt seccomp=unconfined)
  fi

  for volume in "${container_volumes[@]}"; do
    podman_options+=(--volume "${volume}")
  done

  for port in "${container_port_list[@]}"; do
    podman_options+=(--publish "${port}")
  done
}

function action_create() {
  local image_name="registry.fedoraproject.org/fedora:$(rpm -E %fedora)"
  local box_name="$1"
  shift

  parse_config_params "$@"
  set -- "${parse_params[@]}"
  
  if [ "$#" -ne "0" ]; then
    image_name="$1"
    shift
  fi
  
  if [ "$#" -ne "0" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi
  
  checkIfNoBoxExist "$box_name"

  local user_id=$(id -ru)
  gen_podman_options "$box_name"

  if [ -n "$XAUTHORITY" ]; then
    rm -f "/run/user/$user_id/xauthmnbv"
    ln -s "$XAUTHORITY" "/run/user/$user_id/xauthmnbv"
  fi

  local container_name="$container_prefix$box_name"
  podman create --stop-signal SIGABRT --interactive --tty --name "$container_name" "$image_name"
  podman start "$container_name"
  podman exec --user root "$container_name" useradd -m --uid "$user_id" user
  podman exec --user root "$container_name" mkdir -p "/run/user/tmp/pulse"
  podman exec --user root "$container_name" chown -R "$user_id:$user_id" "/run/user/tmp"
  podman stop "$container_name"
  podman commit "$container_name" "$container_name"
  podman rm "$container_name"
  podman create --stop-signal SIGABRT "${podman_options[@]}" --user user "$container_name"

  write_settings_file "$box_name"
}

function reset_container_params() {
  local box_name="$1"
  local user_id=$(id -ru)

  local container_name="$container_prefix$box_name"
  gen_podman_options "$box_name"

  if [ -n "$XAUTHORITY" ]; then
    rm -f "/run/user/$user_id/xauthmnbv"
    ln -s "$XAUTHORITY" "/run/user/$user_id/xauthmnbv"
  fi

  set +e
  podman stop --timeout 2 "$container_name" 2> /dev/null
  podman rm "$container_name" 2> /dev/null
  set -e

  podman create --stop-signal SIGABRT "${podman_options[@]}" --user user "$container_name"
}


function override_container_params() {
  local box_name="$1"
  local user_id=$(id -ru)

  local container_name="$container_prefix$box_name"
  gen_podman_options "$box_name"

  if [ "${container_params["XAUTHORITY"]}" != "$XAUTHORITY" ]; then
    container_params["XAUTHORITY"]="$XAUTHORITY"

    if [ -n "$XAUTHORITY" ]; then
      rm -f "/run/user/$user_id/xauthmnbv"
      ln -s "$XAUTHORITY" "/run/user/$user_id/xauthmnbv"
    fi
    write_settings_file "$box_name"
  fi

  set +e
  podman stop --timeout 2 "$container_name" 2> /dev/null
  podman commit "$container_name" "$container_name" 2> /dev/null
  podman rm "$container_name" 2> /dev/null
  set -e

  podman create --stop-signal SIGABRT "${podman_options[@]}" --user user "$container_name"
}

function action_remove() {
  local box_name="$1"
  shift

  if [ "$#" -ne "0" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
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

  local user_id=$(id -ru)

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"
  
  local reset_container="false"
  if [ "${container_params["display_id"]}" != "$DISPLAY" ]; then
    container_params["display_id"]="$DISPLAY"

    reset_container="true"
  fi

  local session_id="$XDG_SESSION_TYPE:$WAYLAND_DISPLAY"
  if [ "${container_params["session_id"]}" != "$session_id" ]; then
    container_params["session_id"]="$session_id"

    reset_container="true"
  fi

  if [ -n "$XAUTHORITY" ]; then
    rm -rf "/run/user/$user_id/xauthmnbv"
    ln -s "$XAUTHORITY" "/run/user/$user_id/xauthmnbv"
  fi

  if [ "${container_params["XAUTHORITY"]}" != "$XAUTHORITY" ]; then
    container_params["XAUTHORITY"]="$XAUTHORITY"

    #reset_container="true"
    write_settings_file "$box_name"
  fi
  
  if [ "${reset_container}" = "true" ]; then
    override_container_params "$box_name"
    write_settings_file "$box_name"
  fi
  
  gen_podman_options "$box_name"

  local container_name="$container_prefix$box_name"

  if ! podman container exists "$container_name"; then
    podman create --stop-signal SIGABRT "${podman_options[@]}" --user user "$container_name"
  fi

  #xhost +SI:localuser:$(whoami)
  podman start "$container_name"
  podman exec --interactive --tty --user "$userName" "$container_name" "$command" "$@"
}

function action_run_as_system() {
  local box_name="$1"
  shift

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"
  gen_podman_options "$box_name"

  local container_name="$container_prefix$box_name"

  set +e
  podman stop --timeout 2 "$container_name" 2> /dev/null
  podman commit "$container_name" "$container_name" 2> /dev/null
  podman rm "$container_name" 2> /dev/null
  set -e
  
  podman run --interactive --systemd=always --tty --user root "${podman_options[@]}" "$container_name" "/sbin/init"
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
        show_usage_message
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
        show_usage_message
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
    echo "Error: Illegal number of arguments"
    show_usage_message
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
      show_usage_message ;;
  esac
}

function action_read_only() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["read-only"]="$value"
  else
    echo "Error: Illegal value $value"
    show_usage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_net() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  container_params["net"]="$value"

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_ipc() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["ipc"]="$value"
  else
    echo "Error: Illegal value $value"
    show_usage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_gui() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["gui"]="$value"
  else
    echo "Error: Illegal value $value"
    show_usage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_audio() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["audio"]="$value"
  else
    echo "Error: Illegal value $value"
    show_usage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_map_user() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ]; then
    container_params["map-user"]="$value"
  else
    echo "Error: Illegal value $value"
    show_usage_message
    exit 1
  fi

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_security() {
  local box_name="$1"
  local value="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  if [ "$value" = "on" ] || [ "$value" = "off" ] || [ "$value" = "unconfined" ]; then
    container_params["security"]="$value"
  else
    echo "Error: Illegal value $value"
    show_usage_message
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
  local wmclass=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--icon")
        icon_file="$2"
        shift;;
      "--wmclass")
        wmclass="$2"
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
        show_usage_message
        exit 1;;
    esac
    shift
  done

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  local container_name="$container_prefix$box_name"

  if [ $isContainerIcon = true ]; then
    set +e
    podman stop "$container_name" 2> /dev/null
    set -e
    mkdir -p "$HOME/.icons"
    podman cp "$container_name:$icon_file" "$HOME/.icons/"
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

X-Desktop-File-Install-Version=0.23
"

  if [ "$wmclass" != "" ]; then
    desktop="$desktop
StartupWMClass=$wmclass"
  fi

  echo "$desktop" > "${HOME}/.local/share/applications/$box_name-$bin_name.desktop"

  container_desktop_entries["$box_name-$bin_name"]="$box_name-$bin_name"

  write_settings_file "$box_name"
}

function action_desktop_remove() {
  local box_name="$1"
  local bin_name="$2"

  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  rm -f "${HOME}/.local/share/applications/$box_name-$bin_name.desktop"

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  unset container_desktop_entries["$box_name-$bin_name"]

  write_settings_file "$box_name"
}

function desktop_remove_all() {
  local box_name="$1"

  read_settings_file "$box_name"

  for entry in "${container_desktop_entries[@]}"; do
    rm -f "${HOME}/.local/share/applications/$entry.desktop"
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
      show_usage_message ;;
  esac
}

function action_port_add() {
  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  local box_name="$1"
  local port="$2"

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  container_port_list["$port"]="$port"

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_port_remove() {
  if [ "$#" -ne "2" ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
    exit 1
  fi

  local box_name="$1"
  local port="$2"

  checkIfBoxExist "$box_name"
  read_settings_file "$box_name"

  for item in "${container_port_list[@]}"; do
    if [ "$item" = "$port" ]; then
      unset container_port_list["$item"]
    fi
  done

  override_container_params "$box_name"
  write_settings_file "$box_name"
}

function action_port() {
  local action="$1"
  shift

  case "$action" in
    "add") action_port_add "$@" ;;
    "rm") action_port_remove "$@" ;;
    *)
      echo "Unknown command $action"
      show_usage_message ;;
  esac
}

function action_install_tar() {
  if [ "$#" -lt 3 ]; then
    echo "Error: Illegal number of arguments"
    show_usage_message
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
        show_usage_message
        exit 1;;
    esac
    shift
  done

  exec_in_container "$box_name" "root" "mkdir" "-p" "/opt/$app_name"

  local wgetcmd="curl -L $app_url | tar $tar_params"
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
      show_usage_message ;;
  esac
}

function entry() {
  if [ "$#" -eq "0" ]; then
    show_usage_message
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
    "port") action_port "$@" ;;
    "install") action_install "$@" ;;
    "system") action_run_as_system "$@" ;;
    *)
      echo "Unknown command $action"
      show_usage_message ;;
  esac
}

entry "$@"
