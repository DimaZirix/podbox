#!/bin/bash

container_volumes=()
container_params=()

function read_settings_file() {
  local box_name="$1"
  local config_file="/home/user/podbox/test.txt" #"$HOME/.config/podbox/$box_name"
  mkdir -p "$(dirname "$config_file")"

  local line_list=()
  readarray -d $'\n' -t line_list < "$config_file"

  local parse_block=""
  for line in "${line_list[@]}"; do
    if [[ ${line:0:1} == "#" ]]; then
      parse_block="$line"
    elif [ "$parse_block" = "#volumes" ]; then
      container_volumes+=("+$line+")
    elif [ "$parse_block" = "#params" ]; then
      container_params+=("+$line+")
    fi
  done

  unset IFS;

  echo "read_settings $box_name " "${line_list[@]}" "${container_volumes[@]}" pars "${container_params[@]}"
}

function show_ussage_message() {
  echo "error"
}

function parse_container_params() {
  echo "$@"
}

function action_create() {
  local box_name="$1"
  shift
  parse_container_params "$@"

  read_settings_file "$box_name"

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
