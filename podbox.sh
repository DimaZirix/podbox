#!/bin/bash

set -e

function show_ussage_message() {
  echo "error"
}

container_volumes=()
container_params=()

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
      container_volumes+=("+$line+")
    elif [ "$parse_block" = "#params" ]; then
      container_params+=("+$line+")
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
  echo '#end' >"$config_file"

  echo '#params' >>"$config_file"
  for param in "${container_params[@]}"; do
    echo "$param" >>"$config_file"
  done
  echo '#end' >"$config_file"
}


function parse_container_params() {
  echo "$@"
}

function action_create() {
  local box_name="$1"
  shift
  parse_container_params "$@"

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
