#!/bin/bash

set -e

function show_ussage_message() {
  echo "error"
}

container_volumes=()
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
      container_volumes+=("$line")
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
    echo "vol"
  done
  echo '#end' >>"$config_file"

  echo '#params' >>"$config_file"
  for key in "${!container_params[@]}"; do
    echo "${key}=${container_params[$key]}" >>"$config_file"
  done
  echo '#end' >>"$config_file"
}

function parse_config_params() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      "--gui"|"--x11"|"--X11") container_params["gui"]="on";;
      "--audio") container_params["audio"]="on";;
      "--ipc") container_params["ipc"]="on";;
      "--map-user") container_params["map-user"]="on";;
      "--net") container_params["net"]="on";;
      "--volume")
        container_volumes+=("$2")
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
  echo ""
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

  local user_id=$(id -ru)
  local options=$(gen_podman_options)

  podman create --interactive --tty --name "$box_name" --user root registry.fedoraproject.org/fedora:30
  podman start "$box_name"
  podman exec --user root "$box_name" useradd --uid "$user_id" user
  podman stop "$box_name"
  podman commit "$box_name" "$box_name"
  eval "podman create $options --user user $box_name"

  write_settings_file "$box_name"

  echo "action_create $box_name"
}

function entry() {
  local action="$1"
  shift

  case "$action" in
  "create") action_create "$@" ;;
  *) show_ussage_message ;;
  esac
}

entry "$@"
