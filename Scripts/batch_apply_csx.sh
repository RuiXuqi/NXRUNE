#!/usr/bin/env bash
set -o pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
csxDir="$scriptDir/csx"
utmtCli="$scriptDir/utmt/UndertaleModCli"
utmtExe="$scriptDir/utmt/UndertaleModCli.exe"
utmtDll="$scriptDir/utmt/UndertaleModCli.dll"
runLog="$scriptDir/nxrune_patch.log"

if [[ -z "${1:-}" ]]; then
  read -r -p "Please enter DELTARUNE's install path: " gamePath
else
  gamePath="$1"
fi

backupRoot="$gamePath/backup/nxrune"
rollbackDir="$(mktemp -d "$scriptDir/.nxrune_rollback.XXXXXX")"

prepared=()
backupExisting=()
backupNew=()
patchedNames=()
terminalUi=0
uiStatusActive=0
uiRendered=0
utmtWindow=()
utmtWindowMax=8

if [[ -t 1 ]]; then
  terminalUi=1
fi

: > "$runLog"
printf "Target: %s\n\n" "$gamePath" >> "$runLog"

log()
{
  echo "$1"
  printf "%s\n" "$1" >> "$runLog"
}

fail()
{
  clear_patch_ui
  log "[ERROR] $1"
  rollback
  exit 1
}

fail_patch()
{
  clear_patch_ui
  log "Failed to patch $1: $2"
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

render_utmt_window()
{
  local line

  (( terminalUi == 1 )) || return 0

  clear_rendered_lines 0
  for line in "${utmtWindow[@]}"; do
    printf "  %s\n" "$(clip_line "$line")"
  done
  uiRendered="${#utmtWindow[@]}"
}

start_patch_ui()
{
  utmtWindow=()
  uiRendered=0
  uiStatusActive=1
  log "Patching $1..."
}

clear_patch_ui()
{
  if (( uiStatusActive == 1 )); then
    clear_rendered_lines 1
  fi
  uiStatusActive=0
}

append_utmt_line()
{
  local line="$1"
  printf "%s\n" "$line" >> "$runLog"

  if (( terminalUi == 1 )); then
    utmtWindow+=("$line")
    if (( ${#utmtWindow[@]} > utmtWindowMax )); then
      utmtWindow=("${utmtWindow[@]:1}")
    fi
    render_utmt_window
  else
    printf "%s\n" "$line"
  fi
}

run_utmt() {
  if [[ -f "$utmtCli" ]]; then
    [[ -x "$utmtCli" ]] || chmod +x "$utmtCli" || fail "Could not mark '$utmtCli' as executable."
    "$utmtCli" "$@"
  elif [[ -f "$utmtExe" ]]; then
    "$utmtExe" "$@"
  elif [[ -f "$utmtDll" ]] && command -v dotnet >/dev/null 2>&1; then
    dotnet "$utmtDll" "$@"
  else
    fail "UTMT CLI not found in '$scriptDir/utmt'."
  fi
}

target_dir_for() {
  local subDir="$1"
  if [[ "$subDir" == "." ]]; then
    printf "%s\n" "$gamePath"
  else
    printf "%s\n" "$gamePath/$subDir"
  fi
}

backup_dir_for() {
  local subDir="$1"
  if [[ "$subDir" == "." ]]; then
    printf "%s\n" "$backupRoot"
  else
    printf "%s\n" "$backupRoot/$subDir"
  fi
}

state_dir_for() {
  local subDir="$1"
  if [[ "$subDir" == "." ]]; then
    printf "%s\n" "$rollbackDir/backup"
  else
    printf "%s\n" "$rollbackDir/backup/$subDir"
  fi
}

rollback() {
  log "Rolling back..."

  local subDir source backupDir backupFile patchedFile stateDir
  for subDir in "${prepared[@]}"; do
    source="$(target_dir_for "$subDir")"
    backupDir="$(backup_dir_for "$subDir")"
    backupFile="$backupDir/data.win"
    patchedFile="$source/data_patched.win"

    [[ -f "$backupFile" ]] && cp -p "$backupFile" "$source/data.win"
    rm -f "$patchedFile"
  done

  for subDir in "${backupExisting[@]}"; do
    backupDir="$(backup_dir_for "$subDir")"
    backupFile="$backupDir/data.win"
    stateDir="$(state_dir_for "$subDir")"
    mkdir -p "$backupDir"
    cp -p "$stateDir/data.win" "$backupFile"
  done

  for subDir in "${backupNew[@]}"; do
    backupDir="$(backup_dir_for "$subDir")"
    rm -f "$backupDir/data.win"
  done

  find "$backupRoot" -type d -empty -delete 2>/dev/null || true
  rmdir "$gamePath/backup" 2>/dev/null || true
  rm -rf "$rollbackDir"
}

patch_file() {
  local name="$1"
  local subDir="$2"
  local script="$3"

  local source backupDir stateDir backupFile patchedFile
  source="$(target_dir_for "$subDir")"
  backupDir="$(backup_dir_for "$subDir")"
  stateDir="$(state_dir_for "$subDir")"
  backupFile="$backupDir/data.win"
  patchedFile="$source/data_patched.win"

  start_patch_ui "$name"

  [[ -f "$source/data.win" ]] || fail "Source file '$source/data.win' not found."
  [[ -f "$csxDir/$script" ]] || fail_patch "$name" "\"/csx/$script\" not found"

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
  run_utmt load "$source/data.win" -s "$csxDir/$script" -o "$patchedFile" 2>&1 | while IFS= read -r line; do
    append_utmt_line "$line"
  done
  status="${PIPESTATUS[0]}"

  if (( status != 0 )); then
    echo "Failed to patch $name."
    printf "%s\n" "Failed to patch $name." >> "$runLog"
    rm -f "$patchedFile"
    fail "UTMT CLI failed while patching $name."
  fi

  [[ -f "$patchedFile" ]] || fail "UTMT CLI did not produce '$patchedFile'."

  prepared+=("$subDir")
  patchedNames+=("$name")
  clear_patch_ui
  log "Patched $name"
}

commit_file() {
  local name="$1"
  local subDir="$2"
  local source patchedFile

  source="$(target_dir_for "$subDir")"
  patchedFile="$source/data_patched.win"

  mv -f "$patchedFile" "$source/data.win" || fail "Could not replace '$source/data.win' for $name."
}

[[ -d "$gamePath" ]] || fail "Path $gamePath does not exist."
[[ -f "$csxDir/NXRUNE.csx" ]] || fail "CSX scripts folder '$csxDir' is incomplete."

patch_file "Chapter Select" "." NXRUNE.csx
patch_file "Chapter 1" "chapter1_windows" NXRUNE_CH1.csx
patch_file "Chapter 2" "chapter2_windows" NXRUNE_CH2.csx
patch_file "Chapter 3" "chapter3_windows" NXRUNE_CH3.csx
patch_file "Chapter 4" "chapter4_windows" NXRUNE_CH4.csx
patch_file "Chapter 5" "chapter5_windows" NXRUNE_CH5.csx

commit_file "Chapter Select" "."
commit_file "Chapter 1" "chapter1_windows"
commit_file "Chapter 2" "chapter2_windows"
commit_file "Chapter 3" "chapter3_windows"
commit_file "Chapter 4" "chapter4_windows"
commit_file "Chapter 5" "chapter5_windows"

rm -rf "$rollbackDir"

{
  for name in "${patchedNames[@]}"; do
    printf "Patched %s\n" "$name"
  done
  printf "All done! :3\n"
} >> "$runLog"

if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then
  clear
fi

for name in "${patchedNames[@]}"; do
  printf "Patched %s\n" "$name"
done
printf "All done! :3\n"
