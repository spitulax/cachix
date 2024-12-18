#!/usr/bin/env bash

# TODO: invoke helper script via `nix run`

set -euo pipefail

command -v nom >/dev/null
NOM=$?

_nix () {
    nix --experimental-features 'nix-command flakes' $@
}

decolor () {
    sed -e 's/\x1b\[[0-9;]*m//g'
}

paths () {
    _nix path-info --json result/ | jq -r '.[].references.[]'
}

build () {
    echo -e '\033[1mBuilding packages...'
    if [ $NOM -eq 0 ]; then
        _nix build .#cached --log-format internal-json -v --accept-flake-config |& nom --json
    else
        _nix build .#cached --accept-flake-config
    fi
}

push () {
    echo -e '\033[1mPushing packages...'
    cachix push spitulax $(paths)
}

upinput () {
    echo -e '\033[1mUpdating flake inputs...'
    _nix flake update --accept-flake-config
}

uplist () {
    echo -e '\033[1mUpdating package list...'
    local path=$(_nix build .#mypkgs-list --accept-flake-config --json | jq -r '.[].outputs.out')
    install -m644 "$path" list.md
}

# Arguments:
# - DIRNAME: one or more directories to update (pkgs/* or flakes/*)
# - SKIP_EXIST: if 1, skip directories where pkg.json already exists
# - FORCE: if 1, update even if the found version is the same as the old version
# - FLAKE_ONLY: if 1, only update the flakes
# - ALL: if 1, run pkgs-update-scripts-all (will update all packages including excluded packages)
upscript () {
    echo -e '\033[1mRunning update scripts...'

    local pkgs_drv
    local flakes_drv=$(_nix build .#flakes-update-scripts --accept-flake-config --json | jq -r '.[].outputs.out')

    if [ "${FLAKE_ONLY:-0}" -ne 1 ]; then
        local pkg
        if [ "${ALL:-0}" -eq 1 ]; then
            pkg="pkgs-update-scripts-all"
        else
            pkg="pkgs-update-scripts"
        fi
        pkgs_drv=$(_nix build .#${pkg} --accept-flake-config --json | jq -r '.[].outputs.out')
    fi

    for x in $(find -L "$flakes_drv/" -type f -executable); do
        local dirname=$(basename "$x")
        local flakejson_path="$(dirname "$0")/flakes/${dirname}/flake.json"
        local update=0
        if [ -v DIRNAME ]; then
            for y in "${DIRNAME[@]}"; do
                [ "$y" == "flakes/$dirname" ] && update=1 && break
            done
        else
            update=1
        fi
        if [ "${SKIP_EXIST:-0}" -eq 1 ]; then
            [ -f "$flakejson_path" ] && update=0 || update=1
        fi
        if [ "$update" -eq 1 ]; then
            echo -e "\033[1mUpdating flakes/${dirname}...\033[0m"
            local oldrev
            if [ -r "$flakejson_path" ]; then
                oldrev=$(cat "$flakejson_path" | jq -r '.rev')
            fi
            local json
            set +e
            export FORCE="${FORCE:-0}"
            if json=$($x "${oldrev:-}"); then
                echo "$json" > "$flakejson_path"
            else
                echo "Skipped"
            fi
            set -e
        fi
    done

    [ "${FLAKE_ONLY:-0}" -eq 1 ] && exit 0

    for x in $(find -L "$pkgs_drv/" -type f -executable); do
        local dirname=$(basename "$x")
        local pkgjson_path="$(dirname "$0")/pkgs/${dirname}/pkg.json"
        local update=0
        if [ -v DIRNAME ]; then
            for y in "${DIRNAME[@]}"; do
                [ "$y" == "pkgs/$dirname" ] && update=1 && break
            done
        else
            update=1
        fi
        if [ "${SKIP_EXIST:-0}" -eq 1 ]; then
            [ -f "$pkgjson_path" ] && update=0 || update=1
        fi
        if [ "$update" -eq 1 ]; then
            echo -e "\033[1mUpdating pkgs/${dirname}...\033[0m"
            local oldver
            if [ -r "$pkgjson_path" ]; then
                oldver=$(cat "$pkgjson_path" | jq -r '.version')
            fi
            local json
            set +e
            export FORCE="${FORCE:-0}"
            if json=$($x "${oldver:-}"); then
                echo "$json" > "$pkgjson_path"
            else
                echo "Skipped"
            fi
            set -e
        fi
    done
}

commitup () {
    IFS=$'\n'
    local diff=($(git diff -U0 --cached HEAD pkgs.md | grep '^[+-]' | grep -Ev '^(--- a/|\+\+\+ b/)'))
    local pkgs=()
    for x in ${diff[@]}; do
        if [ "${x:0:1}" = "-" ]; then
            name=$(echo "${x:3}" | sed -r 's/^(.*):.*$/\1/')
            oldver=$(echo "${x:3}" | sed -r 's/^.*: (.*)$/\1/')
            newdiff=$(echo "${diff[*]}" | grep -F "$name" | tail -n1)
            newver=$(echo "${newdiff:3}" | sed -r 's/^.*: (.*)$/\1/')
            pkgs+=($(echo -e "${name}\t${oldver}\t${newver}"))
        fi
    done

    local msg="update packages"
    msg+=$'\n'
    for x in ${pkgs[@]}; do
        msg+=$'\n'
        msg+=$(echo "$x" | sed -r 's/^(.*)\t(.*)\t(.*)$/\1: \2 -> \3/')
    done
    git commit -m "$msg"
    IFS=' '
}

usage () {
    echo "Arguments are passed via environment variables."
    echo "Subcommands:"
    echo "- build"
    echo "- commitup"
    echo "- pushinput"
    echo "- pushpkgs"
    echo "- upall"
    echo "- upinput"
    echo "- uplist"
    echo "- uppkgs"
    echo "- upscript"
}

[ $# -ne 1 ] && usage && exit 1

case "$1" in
"upinput")
    upinput
    ;;

"build")
    build
    ;;

"pushinput")
    echo -e '\033[1mPushing inputs to cachix...'
    _nix flake archive --accept-flake-config --json \
        | jq -r '.path,(.inputs|to_entries[].value.path)' \
        | cachix push spitulax
    ;;

"pushpkgs")
    push
    ;;

"uplist")
    uplist
    ;;

"upscript")
    upscript
    ;;

"uppkgs")
    upscript && build && push && uplist
    ;;

"upall")
    upinput && upscript && build && push && uplist
    ;;

"commitup")
    commitup
    ;;

*)
    usage
    exit 1
    ;;
esac
