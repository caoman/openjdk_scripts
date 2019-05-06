#!/bin/bash
#
# Create a webrev in a temporary directory and upload it to cr.openjdk.java.net.
# The webrev is automatically named in the "<BugID>/webrev.XX" format.
# This script is suitable for users of "hg commit --amend" and "hg rebase"
# for working with OpenJDK upstream sources. It may not work for users of
# MqExtension.
#
# Prerequisites:
#   1. Current directory is root of mercurial repository.
#   2. The tip is the commit containing changes for the webrev.
#   3. The tip commit's description starts with "BugID:".
#
# Arguments:
#   -N:   Pass "-N -r 'p1(-1)'" to webrev script. This works with local Mercurial
#         branches and pending changes in working directory, but will create a
#         .patch file instead of .changeset file.
#
#   -D <name>: Does not check or extract bug ID from commit message, but put
#              webrevs in directory with <name> on remote host.
#

set -euo pipefail

declare -r USERNAME="$USER"
declare -r WEBREV="$HOME/ws/code-tools/webrev/webrev.ksh"
declare -r PUBHOST="cr.openjdk.java.net"

function die() { printf "%s: $1\n" "$0" "${@:2}" >&2; exit 2; }

function get_bugID() {
  local first_line
  first_line="$(hg log -T '{firstline(desc)}' -r -1)"
  if [[ "$first_line" =~ ^([0-9]+): ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    die "Can't parse tip commit's description: $first_line"
  fi
}

function get_remote_webrev_name() {
  local -r remote_dir="$1"
  local -r webrev_host="$2"
  local root_content
  root_content="$(sftp -q "$webrev_host" <<< "ls -1")"
  readonly root_content
  # Creates $remote_dir directory if it doesn't exist
  if [[ -z "$(grep "^$remote_dir$" - <<< "$root_content")" ]]; then
    sftp -q "$webrev_host" <<< "mkdir $remote_dir" &> /dev/null
  fi
  local existing_webrevs
  existing_webrevs="$(sftp -q "$webrev_host:$remote_dir" <<< "ls -1")"
  readonly existing_webrevs
  local -r last_webrev="${existing_webrevs##*$'\n'}"
  local rev="00"
  if [[ "$last_webrev" =~ ^webrev[.]([0-9][0-9])$ ]]; then
    rev=$((${BASH_REMATCH[1]} + 1))
    rev="$(printf '%02d' "$rev")"
  elif [[ "$last_webrev" =~ ^webrev[.].+$ ]]; then
    # Generate a random suffix as rev, if last_webrev does not end in 00-99.
    rev="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"
  fi
  if [[ -n "$(grep "^webrev[.]$rev$" - <<< "$existing_webrevs")" ]]; then
    die "'webrev.$rev' already exists in '$existing_webrevs'"
  fi
  echo "webrev.$rev"
}


function main() {
  local webrev_N=0
  local dir_arg=""
  while [[ "$#" -gt 0 ]]; do
    opt="$1"; shift;
    case "$opt" in
      -N) webrev_N=1 ;;
      -D) dir_arg="$1" ;;
    esac
  done

  # 'local -r var=$(foo)' will ignore 'set -e' if foo fails.
  # We need to split it into three statements.
  local remote_dir
  local bugID=""

  if [[ -z "$dir_arg" ]]; then
    bugID="$(get_bugID)"
    remote_dir="$bugID"
  else
    remote_dir="$dir_arg"
  fi
  readonly bugID
  readonly remote_dir

  local outdir
  outdir="$(mktemp -d -p /tmp "webrev${remote_dir}_XXXX")"
  readonly outdir

  local repo_url
  repo_url="$(hg paths default)"
  readonly repo_url

  # For -N and local mercurial branches:
  # webrev.ksh does not handle mercurial branches well.
  # For webrev.ksh to create comments correctly under mercurial branches, user
  # needs to comment out "elif [[ -n $FIRST_CREV ]]" block in
  # comments_from_mercurial(), so it always runs the
  # "hg log -l1 --removed --template ..." command.
  local -a webrev_args
  if ((webrev_N)); then
    webrev_args+=('-N' '-r' 'p1(-1)')
  fi
  if [[ -n "$bugID" ]]; then
    webrev_args+=('-c' "$bugID")
  fi

  ksh "$WEBREV" -m "${webrev_args[@]}" -p "$repo_url" -o "$outdir"
  chmod -R a+rX "$outdir"

  local -r webrev_host="$USERNAME@$PUBHOST"
  local webrev_name
  webrev_name="$(get_remote_webrev_name "$remote_dir" "$webrev_host")"
  readonly webrev_name
  rsync --chmod=a+rX -av "$outdir/webrev/" "$webrev_host:$remote_dir/$webrev_name/"
  echo "Webrev: https://cr.openjdk.java.net/~$USERNAME/$remote_dir/$webrev_name/"
  if [[ -n "$bugID" ]]; then
    echo "Bug: https://bugs.openjdk.java.net/browse/JDK-$bugID"
  fi
}

main "$@"

