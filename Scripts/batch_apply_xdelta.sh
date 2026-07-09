#!/usr/bin/env bash
set -o pipefail

if [[ -z "${1:-}" ]]; then
  read -r -p "Please enter DELTARUNE's install path: " gamePath
else
  gamePath="$1"
fi

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rollbackDir="$(mktemp -d "$scriptDir/.nxrune_rollback.XXXXXX")"
backupRoot="$gamePath/backup/nxrune"
patchDir="$scriptDir/xdelta"
xdeltaBin="$scriptDir/xdelta3"

if [[ ! -f "$xdeltaBin" ]]; then
  xdeltaBin="$scriptDir/xdelta.exe"
fi

if [[ ! -f "$xdeltaBin" ]]; then
  xdeltaBin="$scriptDir/xdelta3.exe"
fi

prepared=()
backupExisting=()
backupNew=()
patchedNames=()
terminalUi=0
uiStatusActive=0
uiRendered=0
tailWindow=()
tailWindowMax=8

if [[ -t 1 ]]; then
  terminalUi=1
fi

fail()
{
  clear_patch_ui
  echo "[ERROR] $1"
  rollback
  exit 1
}

fail_patch()
{
  clear_patch_ui
  echo "Failed to patch $1: $2"
  rollback
  exit 1
}

terminal_width()
{
  local cols
  cols="$(tput cols 2>/dev/null || printf "100")"
  if [[ "$cols" =~ ^[0-9]+$ ]] && (( cols >= 20 )); then
    printf "%s\n" "$cols"
  else
    printf "100\n"
  fi
}

clip_line()
{
  local line="$1"
  local cols limit
  cols="$(terminal_width)"
  limit=$((cols - 3))

  if (( ${#line} > limit )); then
    printf "%s...\n" "${line:0:$((limit - 3))}"
  else
    printf "%s\n" "$line"
  fi
}

clear_rendered_lines()
{
  local includeStatus="${1:-0}"
  local count=$((uiRendered + includeStatus))

  if (( terminalUi == 1 && count > 0 )); then
    printf "\033[%dA\033[J" "$count"
  fi

  uiRendered=0
}

render_tail_window()
{
  local line

  (( terminalUi == 1 )) || return 0

  clear_rendered_lines 0
  for line in "${tailWindow[@]}"; do
    printf "  %s\n" "$(clip_line "$line")"
  done
  uiRendered="${#tailWindow[@]}"
}

start_patch_ui()
{
  tailWindow=()
  uiRendered=0
  uiStatusActive=1
  echo "Patching $1..."
}

clear_patch_ui()
{
  if (( uiStatusActive == 1 )); then
    clear_rendered_lines 1
  fi
  uiStatusActive=0
}

append_xdelta_line()
{
  local line="$1"
  if (( terminalUi == 1 )); then
    tailWindow+=("$line")
    if (( ${#tailWindow[@]} > tailWindowMax )); then
      tailWindow=("${tailWindow[@]:1}")
    fi
    render_tail_window
  else
    printf "%s\n" "$line"
  fi
}

rollback() {
  echo "Rolling back..."

  local subDir source backupDir backupFile patchedFile stateDir
  for subDir in "${prepared[@]}"; do
    if [[ "$subDir" == "." ]]; then
      source="$gamePath"
      backupDir="$backupRoot"
      stateDir="$rollbackDir/backup"
    else
      source="$gamePath/$subDir"
      backupDir="$backupRoot/$subDir"
      stateDir="$rollbackDir/backup/$subDir"
    fi

    backupFile="$backupDir/data.win"
    patchedFile="$source/data_patched.win"

    [[ -f "$backupFile" ]] && cp -p "$backupFile" "$source/data.win"
    rm -f "$patchedFile"
  done

  for subDir in "${backupExisting[@]}"; do
    if [[ "$subDir" == "." ]]; then
      backupDir="$backupRoot"
      stateDir="$rollbackDir/backup"
    else
      backupDir="$backupRoot/$subDir"
      stateDir="$rollbackDir/backup/$subDir"
    fi

    mkdir -p "$backupDir"
    cp -p "$stateDir/data.win" "$backupDir/data.win"
  done

  for subDir in "${backupNew[@]}"; do
    if [[ "$subDir" == "." ]]; then
      backupDir="$backupRoot"
    else
      backupDir="$backupRoot/$subDir"
    fi

    rm -f "$backupDir/data.win"
  done

  find "$backupRoot" -type d -empty -delete 2>/dev/null || true
  rmdir "$gamePath/backup" 2>/dev/null || true
  rm -rf "$rollbackDir"
}

patch_file() {
  local name="$1"
  local subDir="$2"
  local patch="$3"

  local source backupDir stateDir backupFile patchedFile
  if [[ "$subDir" == "." ]]; then
    source="$gamePath"
    backupDir="$backupRoot"
    stateDir="$rollbackDir/backup"
  else
    source="$gamePath/$subDir"
    backupDir="$backupRoot/$subDir"
    stateDir="$rollbackDir/backup/$subDir"
  fi

  backupFile="$backupDir/data.win"
  patchedFile="$source/data_patched.win"

  [[ -f "$source/data.win" ]] || fail "Source file '$source/data.win' not found."
  [[ -f "$patchDir/$patch" ]] || fail_patch "$name" "\"/xdelta/$patch\" not found"

  start_patch_ui "$name"

  if [[ -f "$backupFile" ]]; then
    mkdir -p "$stateDir"
    cp -p "$backupFile" "$stateDir/data.win" || fail "Could not preserve existing backup '$backupFile'."
    backupExisting+=("$subDir")
  else
    backupNew+=("$subDir")
  fi

  mkdir -p "$backupDir"
  cp -p "$source/data.win" "$backupFile" || fail "Could not create backup '$backupFile'."

  rm -f "$patchedFile"
  set +m 2>/dev/null || true
  shopt -s lastpipe 2>/dev/null || true
  "$xdeltaBin" -d -f -s "$source/data.win" "$patchDir/$patch" "$patchedFile" 2>&1 | while IFS= read -r line; do
    append_xdelta_line "$line"
  done
  status="${PIPESTATUS[0]}"

  if (( status != 0 )); then
    echo "Failed to patch $name."
    rm -f "$patchedFile"
    fail "xdelta3 failed while patching $name."
  fi

  [[ -f "$patchedFile" ]] || fail "xdelta3 did not produce '$patchedFile'."

  prepared+=("$subDir")
  patchedNames+=("$name")
  clear_patch_ui
  echo "Patched $name"
}

commit_file() {
  local subDir="$1"
  local source patchedFile

  if [[ "$subDir" == "." ]]; then
    source="$gamePath"
  else
    source="$gamePath/$subDir"
  fi

  patchedFile="$source/data_patched.win"
  mv -f "$patchedFile" "$source/data.win" || fail "Could not replace '$source/data.win'."
}

[[ -d "$gamePath" ]] || fail "Path $gamePath does not exist."
[[ -f "$xdeltaBin" ]] || fail "xdelta executable not found."
[[ -d "$patchDir" ]] || fail "xdelta folder not found."

patch_file "Chapter Select" "." "chapter_select.xdelta"
patch_file "Chapter 1" "chapter1_windows" "chapter1.xdelta"
patch_file "Chapter 2" "chapter2_windows" "chapter2.xdelta"
patch_file "Chapter 3" "chapter3_windows" "chapter3.xdelta"
patch_file "Chapter 4" "chapter4_windows" "chapter4.xdelta"
patch_file "Chapter 5" "chapter5_windows" "chapter5.xdelta"

commit_file "."
commit_file "chapter1_windows"
commit_file "chapter2_windows"
commit_file "chapter3_windows"
commit_file "chapter4_windows"
commit_file "chapter5_windows"

rm -rf "$rollbackDir"
echo "All done! :3"
