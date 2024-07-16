#!/usr/bin/env bash

command -v nom >/dev/null
NOM=$?

cleanse () {
    sed -e 's/\x1b\[[0-9;]*m//g'
}

paths () {
    nix path-info --json result/ | jq -r '.[].references.[]'
}

build () {
    echo -e '\033[1mBuilding packages...'
    if [ $NOM -eq 0 ]; then
        nix build .#all --log-format internal-json -v --accept-flake-config |& nom --json
    else
        nix build .#all --accept-flake-config
    fi
}

listpkgs () {
    local list=()
    for path in $(paths); do
        local env=$(nix derivation show $path | jq -r '.[].env')
        local name=$(echo -n $env | jq -r 'if .pname == null then .name else .pname end')
        local version=$(echo -n $env | jq -r '.version')
        list+=($(echo -n "$name\"$version"))
    done
    IFS=$'\n' list=($(sort <<< "${list[*]}"))
    for pkg in ${list[@]}; do
        local name=$(echo $pkg | sed -r 's/^(.*)".*$/\1/')
        local version=$(echo $pkg | sed -r 's/^.*"//')
        echo -e "- \033[1m$name\033[0m: \033[2m$version\033[0m"
    done
}

listpkgsName () {
    listpkgs | sed -r 's/^- (.*): .*$/\1/' | cleanse
}

push () {
    echo -e '\033[1mPushing packages...'
    cachix push spitulax `paths`
}

upinput () {
    echo -e '\033[1mUpdating flake inputs...'
    nix flake update --accept-flake-config
}

uplist () {
    echo "<!--- This list was auto-generated by ./helper.sh. DO NOT edit this file manually. -->" > pkgs.md
    echo >> pkgs.md
    echo '<h2 align="center">List of Packages</h2>' >> pkgs.md
    echo >> pkgs.md
    echo '_(The latest version available in the nix store)_' >> pkgs.md
    echo >> pkgs.md
    while IFS= read -r line; do
        echo $line | cleanse >> pkgs.md
    done <<< "$(listpkgs)"
}

usage () {
    echo "upinput"
    echo "build"
    echo "pushinput"
    echo "pushpkgs"
    echo "uplist"
    echo "uppkgs"
    echo "upall"
    echo "listpkgs"
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
    nix flake archive --accept-flake-config --json \
        | jq -r '.path,(.inputs|to_entries[].value.path)' \
        | cachix push spitulax
    ;;

"pushpkgs")
    push
    ;;

"uplist")
    uplist
    ;;

"uppkgs")
    build && push && uplist
    ;;

"upall")
    upinput && build && push && uplist
    ;;

"listpkgs")
    listpkgs
    ;;

*)
    usage
    exit 1
    ;;
esac
