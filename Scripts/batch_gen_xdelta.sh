#!/usr/bin/env bash

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
outputDir="$scriptDir/xdelta"

if [[ -z "${1:-}" ]]; then
  read -r -p "Please enter DELTARUNE's install path: " gamePath
else
  gamePath="$1"
fi

fail()
{
  echo "[ERROR] $1"
  exit 1
}

gen_patch() {
  local name="$1"
  local subDir="$2"
  local patch="$3"

  local target
  local backup
  if [[ "$subDir" == "." ]]; then
    target="$gamePath"
    backup="$gamePath/backup/nxrune"
  else
    target="$gamePath/$subDir"
    backup="$gamePath/backup/nxrune/$subDir"
  fi

  [[ -f "$backup/data.win" ]] || fail "Backup file '$backup/data.win' not found."
  [[ -f "$target/data.win" ]] || fail "Target file '$target/data.win' not found."

  echo "Generating $name..."
  if ! "$scriptDir/xdelta3" -e -f -s "$backup/data.win" "$target/data.win" "$outputDir/$patch"; then
    echo "Failed to generate $name."
    return 1
  fi
}

[[ -d "$gamePath" ]] || fail "Path $gamePath does not exist."
[[ -f "$scriptDir/xdelta3" ]] || fail "xdelta3 not found."
mkdir -p "$outputDir"

gen_patch "Chapter Select" "." chapter_select.xdelta
gen_patch "Chapter 1" "chapter1_windows" chapter1.xdelta
gen_patch "Chapter 2" "chapter2_windows" chapter2.xdelta
gen_patch "Chapter 3" "chapter3_windows" chapter3.xdelta
gen_patch "Chapter 4" "chapter4_windows" chapter4.xdelta
gen_patch "Chapter 5" "chapter5_windows" chapter5.xdelta

echo "All done! :3"
