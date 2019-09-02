#!/bin/bash

container_volumes=()

function read_settings_file() {
  echo "ok"
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

  echo "$box_name"
}

function entry() {
  read_settings_file

  local action="$1"
  shift

  case "$action" in
    "create") action_create "$@";;
    *) show_ussage_message ;;
  esac
}

entry "$@"
