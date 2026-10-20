#!/usr/bin/env bash
# Open a file someone sent you with `x vault share`.
#
#   curl -fsSL <raw URL of this file> | bash -s -- <passphrase> <file.age> [--to DIR]
#
# What it does, in order:
#   1. Finds <file.age> in the current folder or in ~/Downloads.
#   2. Downloads the `age` decryption tool (a pinned release from
#      github.com/FiloSottile/age) into a temporary folder and checks it
#      against the SHA-256 written below. Nothing is installed.
#   3. Decrypts and unpacks into a temporary folder next to the destination,
#      shows what it got, and asks before moving it into place: the folder
#      the .age file is in, or DIR (using sudo only if DIR isn't writable).
#   4. Removes the temporary folder (and, if you agree, the .age file).
set -euo pipefail

AGE_VERSION=v1.3.2
age_sha256() {
    case $1 in
        darwin-arm64) echo e2020b073c44f692685a24d6abc378817eb81ffaaf49fd0531ef8565f767f2f5 ;;
        darwin-amd64) echo 1d1e4bc66e1427edad7739ae7616157de0e79db8b6d2a1497d7d9925fb06a539 ;;
        linux-arm64)  echo 6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4 ;;
        linux-amd64)  echo cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10 ;;
        *) return 1 ;;
    esac
}

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    bold=$'\e[1m' dim=$'\e[2m' green=$'\e[32m' red=$'\e[31m' reset=$'\e[0m'
else
    bold='' dim='' green='' red='' reset=''
fi
step() { printf '%s▸ %s%s\n' "$bold" "$*" "$reset" >&2; }
ok()   { printf '%s✔%s %s\n' "$green" "$reset" "$*" >&2; }
die()  { printf '%s✘ %s%s\n' "$red" "$*" "$reset" >&2; exit 1; }
present() { [ -e "$1" ] || [ -L "$1" ]; }
ask()  { # ask <question> [default y|n]
    local reply hint='[y/N]'
    [ "${2:-n}" = y ] && hint='[Y/n]'
    printf '%s %s ' "$1" "$hint" >&2
    { read -r reply </dev/tty; } 2>/dev/null || reply=''
    reply=${reply:-${2:-n}}
    case $reply in [yY]*) return 0 ;; *) return 1 ;; esac
}

# Everything runs from main, called on the last line, so bash has read the
# whole script before doing anything (it arrives through a pipe).
main() {
    [ $# -ge 2 ] || die "Usage: … | bash -s -- <passphrase> <file.age> [--to DIR]"
    local pass=$1 want=$2 to='' file='' stem dir newest os arch expected got dest entry item size note sudo=''
    local -a items=()
    shift 2
    while [ $# -gt 0 ]; do
        case $1 in
            --to) [ $# -ge 2 ] || die "--to needs a folder"; to=$2; shift 2 ;;
            *)    die "Unknown option: $1" ;;
        esac
    done

    # --- 1. find the file -----------------------------------------------------------
    # Browsers rename repeat downloads ("share-x (1).age"), so take the newest match.
    stem=${want%.age}
    for dir in "$PWD" "$HOME/Downloads"; do
        [ -f "$dir/$want" ] && { file="$dir/$want"; break; }
        # ls -t is the portable way to get the newest; the names are ours.
        # shellcheck disable=SC2012
        newest=$(ls -t "$dir/$stem"*.age 2>/dev/null | head -n 1 || true)
        [ -n "$newest" ] && { file=$newest; break; }
    done
    [ -f "$want" ] && file=$want
    [ -n "$file" ] || die "Couldn't find $want here or in ~/Downloads. Download it first, or run this from its folder."
    file=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")
    ok "Found $file"

    # --- 2. fetch age ---------------------------------------------------------------
    case $(uname -s) in
        Darwin) os=darwin ;;
        Linux)  os=linux ;;
        *)      die "Unsupported system: $(uname -s)" ;;
    esac
    case $(uname -m) in
        arm64|aarch64) arch=arm64 ;;
        x86_64|amd64)  arch=amd64 ;;
        *)             die "Unsupported processor: $(uname -m)" ;;
    esac
    expected=$(age_sha256 "$os-$arch") || die "No age build for $os-$arch"

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/open-share.XXXXXX")
    stage=''
    # The stage first: it may sit inside $tmp, and an archive can hold
    # read-only folders, which rm -rf can't empty.
    cleanup() {
        if [ -n "$stage" ]; then
            chmod -R u+w "$stage" 2>/dev/null || true
            rm -rf "$stage" 2>/dev/null || true
        fi
        rm -rf "$tmp" 2>/dev/null || true
    }
    trap cleanup EXIT

    step "Fetching the decryption tool (age $AGE_VERSION)"
    curl -fsSL -o "$tmp/age.tar.gz" \
        "https://github.com/FiloSottile/age/releases/download/$AGE_VERSION/age-$AGE_VERSION-$os-$arch.tar.gz" ||
        die "Download of age failed."
    if command -v shasum >/dev/null; then
        got=$(shasum -a 256 "$tmp/age.tar.gz" | cut -d' ' -f1)
    else
        got=$(sha256sum "$tmp/age.tar.gz" | cut -d' ' -f1)
    fi
    [ "$got" = "$expected" ] || die "The downloaded age doesn't match its known checksum; stopping."
    tar -xzf "$tmp/age.tar.gz" -C "$tmp"
    PATH="$tmp/age:$PATH"
    ok "age verified"

    # --- 3. decrypt and unpack ------------------------------------------------------
    to=${to/#\~/$HOME}   # "--to ~/Apps" arrives quoted, so expand it here
    dest=${to:-$(dirname "$file")}
    if [ ! -d "$dest" ]; then
        ask "$dest doesn't exist. Create it?" y || die "Stopped."
        mkdir -p "$dest" 2>/dev/null || sudo mkdir -p "$dest"
    fi
    dest=$(cd "$dest" && pwd)
    # Unpack on the same disk as the destination so the final move is instant;
    # fall back to the temp folder when the destination isn't writable.
    stage=$(mktemp -d "$dest/.open-share.XXXXXX" 2>/dev/null || mktemp -d "$tmp/stage.XXXXXX")

    step "Decrypting $(basename "$file")"
    exec 3< <(printf '%s\n' "$pass")
    AGE_PASSPHRASE_FD=3 age -d -j batchpass "$file" | tar -xzf - -C "$stage" ||
        die "Decryption failed: wrong passphrase, or the file is incomplete or damaged."
    exec 3<&-
    ok "Decrypted and checked (any tampering would have stopped it)"

    # .[!.]* and ..?* together match every dotfile but . and ..
    for entry in "$stage"/* "$stage"/.[!.]* "$stage"/..?*; do
        if present "$entry"; then items+=("$(basename "$entry")"); fi
    done
    [ ${#items[@]} -gt 0 ] || die "The archive was empty."

    printf '\n%sThis will put into %s:%s\n' "$bold" "$dest" "$reset" >&2
    for item in "${items[@]}"; do
        size=$(du -sh "$stage/$item" 2>/dev/null | cut -f1)
        note=''
        if present "$dest/$item"; then note=" ${red}(replaces the existing one)${reset}"; fi
        printf '  %s %s(%s)%s%s\n' "$item" "$dim" "$size" "$reset" "$note" >&2
    done
    echo >&2
    ask "Go ahead?" y || die "Stopped; nothing was changed."

    [ -w "$dest" ] || { sudo=sudo; step "$dest needs administrator rights (sudo)"; }
    for item in "${items[@]}"; do
        if present "$dest/$item"; then
            $sudo chmod -R u+w "$dest/$item" 2>/dev/null || true
            $sudo rm -rf "$dest/$item"
        fi
        $sudo mv "$stage/$item" "$dest/$item"
        ok "$dest/$item"
    done

    if ask "Delete the downloaded $(basename "$file")?" y; then
        rm -f "$file" && ok "Removed $(basename "$file")"
    fi
    printf '%sDone.%s\n' "$green" "$reset" >&2
}

main "$@"
