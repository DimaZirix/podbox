#!/bin/bash

container_volumes=()

function read_settings_file() {
  local box_name="$1"

  echo "read_settings $box_name"
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
    "create") action_create "$@";;
    *) show_ussage_message ;;
  esac
}

entry "$@"
