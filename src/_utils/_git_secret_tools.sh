#!/usr/bin/env bash

# Global variables:
WORKING_DIRECTORY="$PWD"  # shellcheck disable=2034

# Folders:
SECRETS_DIR=".gitsecret"
SECRETS_DIR_KEYS="$SECRETS_DIR/keys"
SECRETS_DIR_PATHS="$SECRETS_DIR/paths"

# Files:
SECRETS_DIR_KEYS_MAPPING="$SECRETS_DIR_KEYS/mapping.cfg"  # shellcheck disable=2034
SECRETS_DIR_KEYS_TRUSTDB="$SECRETS_DIR_KEYS/trustdb.gpg"  # shellcheck disable=2034

SECRETS_DIR_PATHS_MAPPING="$SECRETS_DIR_PATHS/mapping.cfg"  # shellcheck disable=2034

: "${SECRETS_EXTENSION:=".secret"}"

# Commands:
: "${SECRETS_GPG_COMMAND:="gpg"}"
GPGLOCAL="$SECRETS_GPG_COMMAND --homedir=$SECRETS_DIR_KEYS --no-permission-warning"


# Inner bash :

function _function_exists {
  declare -f -F "$1" > /dev/null
  echo $?
}


# OS based :

function _os_based {
  # Pass function name as first parameter.
  # It will be invoked as os-based function with the postfix.

  case "$(uname -s)" in

    Darwin)
      "$1_osx" "${@:2}"
    ;;

    Linux)
      "$1_linux" "${@:2}"
    ;;

    # TODO: add MS Windows support.
    # CYGWIN*|MINGW32*|MSYS*)
    #   $1_ms ${@:2}
    # ;;

    *)
      _abort 'unsupported OS.'
    ;;
  esac
}


# File System :

function _set_config {
  # First parameter is the KEY, second is VALUE, third is filename.

  # The exit status is 0 (true) if the name was found, 1 (false) if not:
  local contains
  contains=$(grep -Fq "$1" "$3"; echo "$?")

  if [[ "$contains" -eq 0 ]]; then
    _os_based __replace_in_file "$@"
  elif [[ "$contains" -eq 1 ]]; then
    echo "$1 = $2" >> "$3"
  fi
}


function _file_has_line {
  # First parameter is the KEY, second is the filename.

  local contains
  contains=$(grep -qw "$1" "$2"; echo $?)
  # 0 on contains, 1 for error.
  echo "$contains";
}


function _delete_line {
  local escaped_path
  escaped_path=$(echo "$1" | sed -e 's/[\/&]/\\&/g')
  sed -i.bak "/$escaped_path/d" "$2"
}


function _temporary_file {
  # This function creates temporary file
  # which will be removed on system exit.
  filename=$(_os_based __temp_file)  # is not `local` on purpose.

  trap 'echo "cleaning up..."; rm -f "$filename";' EXIT
}


function _unique_filename {
  # First parameter is base-path, second is filename,
  # third is optional extension.
  local n=0 result=$2
  while true; do
    if [[ ! -f "$1/$result" ]]; then
      break
    fi

    n=$(( n + 1 ))
    result="${2}-${n}"
  done
  echo "$result"
}


# Manuals:

function _show_manual_for {
  local function_name="$1"
  man "git-secret-${function_name}"
  exit 0
}


# VCS :

function _check_ignore {
  git check-ignore --no-index -q "$1";
  echo $?
}


function _add_ignored_file {
  if [[ ! -f ".gitignore" ]]; then
    touch ".gitignore"
  fi

  echo "$1" >> ".gitignore"
}


# Logic :

function _abort {
  >&2 echo "$1 abort."
  exit 1
}


function _secrets_dir_exists {
  if [[ ! -d "$SECRETS_DIR" ]]; then
    _abort "$SECRETS_DIR does not exist."
  fi
}


function _user_required {
  _secrets_dir_exists

  local error_message="no users found. run 'git secret tell' before adding files."
  if [[ ! -f "$SECRETS_DIR_KEYS_TRUSTDB" ]]; then
    _abort "$error_message"
  fi

  local keys_exist
  keys_exist=$($GPGLOCAL -n --list-keys --with-colon)
  if [[ -z "$keys_exist" ]]; then
    _abort "$error_message"
  fi
}


function _get_raw_filename {
  echo "$(dirname "$1")/$(basename "$1" "$SECRETS_EXTENSION")" | sed -e 's#^\./##'
}


function _get_encrypted_filename {
  local filename
  filename="$(dirname "$1")/$(basename "$1" "$SECRETS_EXTENSION")"
  echo "${filename}${SECRETS_EXTENSION}" | sed -e 's#^\./##'
}


function _get_users_in_keyring {
  local result
  result=$($GPGLOCAL --list-public-keys --with-colon | sed -n 's/.*<\(.*\)>.*/\1/p')
  echo "$result"
}


function _get_recepients {
  local result
  result=$($GPGLOCAL --list-public-keys --with-colon | sed -n 's/.*<\(.*\)>.*/-r\1/p')
  echo "$result"
}


function _decrypt {
  # required:
  local filename="$1"

  # optional:
  local write_to_file=${2:-1} # can be 0 or 1
  local force=${3:-0} # can be 0 or 1
  local homedir=${4:-""}
  local passphrase=${5:-""}

  local encrypted_filename
  encrypted_filename=$(_get_encrypted_filename "$filename")

  local base="$SECRETS_GPG_COMMAND --use-agent -q --decrypt --no-permission-warning"

  if [[ "$write_to_file" -eq 1 ]]; then
    base="$base -o $filename"
  fi

  if [[ "$force" -eq 1 ]]; then
    base="$base --yes"
  fi

  if [[ ! -z "$homedir" ]]; then
    base="$base --homedir=$homedir"
  fi

  if [[ ! -z "$passphrase" ]]; then
    echo "$passphrase" | $base --batch --yes --no-tty --passphrase-fd 0 \
      "$encrypted_filename"
  else
    $base "$encrypted_filename"
  fi
}
