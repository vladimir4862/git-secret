#!/usr/bin/env bash


function tell {
  local email
  local homedir

  # A POSIX variable
  # Reset in case getopts has been used previously in the shell.
  OPTIND=1

  while getopts "h?md:" opt; do
    case "$opt" in
      h) _show_manual_for "tell";;

      m) # Set email of the git current user:
        email=$(git config user.email) || _abort "'git config user.email' is not set."
      ;;

      d) homedir=$OPTARG;;
    esac
  done

  shift $((OPTIND-1))
  [ "$1" = "--" ] && shift

  # Moved to enable viewing a manual without validation:
  _secrets_dir_exists

  # Custom argument-parsing:
  if [[ -z $email ]]; then
    # Email was not set via `-m` and is in $1:
    test ! -z "$1" && email="$1"; shift || _abort "first argument must be an email address."
  fi

  # This file will be removed automatically:
  _temporary_file  # note, that `_temporary_file` will export `filename` var.
  # shellcheck disable=2154
  local keyfile="$filename"

  if [[ -z "$homedir" ]]; then
    $SECRETS_GPG_COMMAND --export -a "$email" > "$keyfile"
  else
    # It means that homedir is set as an extra argument via `-d`:
    $SECRETS_GPG_COMMAND --no-permission-warning --homedir="$homedir" \
      --export -a "$email" > "$keyfile"
  fi

  if [[ ! -s "$keyfile" ]]; then
    _abort 'gpg key is empty. check your key name: "gpg --list-keys".'
  fi

  # Importing public key to the local keychain:
  $GPGLOCAL --import "$keyfile" > /dev/null 2>&1

  echo "done. $email added as a person who knows the secret."
}
