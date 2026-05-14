#!/usr/bin/env bash
# get base dir regardless of execution location
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
. "$(dirname "$SOURCE")/init.sh"
set -e

paper_dir="$basedir/Paper"
paper_crlf_paths=(paper scripts Spigot-API-Patches Spigot-Server-Patches)

restorePaperTrackedFiles() {
  git -C "$paper_dir" checkout -f -- "${paper_crlf_paths[@]}" >/dev/null 2>&1 || true
}

preparePaperScripts() {
  if ! git -C "$paper_dir" diff --quiet -- "${paper_crlf_paths[@]}" ||
     ! git -C "$paper_dir" diff --cached --quiet -- "${paper_crlf_paths[@]}"; then
    echo "Paper has local changes in scripts or patch files; refusing to normalize them temporarily."
    echo "Commit, stash, or restore those Paper changes before running upstream."
    exit 1
  fi

  trap restorePaperTrackedFiles EXIT

  perl -pi -e 's/\r\n/\n/g' \
    "$paper_dir/paper" \
    "$paper_dir"/scripts/*.sh \
    "$paper_dir"/Spigot-API-Patches/*.patch \
    "$paper_dir"/Spigot-Server-Patches/*.patch
}

checkPaperGeneratedRepo() {
  local target="$paper_dir/$1"
  if [ -d "$target" ] && [ ! -e "$target/.git" ]; then
    echo "$target exists but is not a standalone git repository."
    echo "Move or remove it before applying Paper patches."
    exit 1
  fi
}

if [[ "$1" == up* ]]; then
  (
    cd "$paper_dir/" || exit
    git fetch && git reset --hard origin/master
    cd ../
    git add Paper
  )
fi

preparePaperScripts
checkPaperGeneratedRepo Paper-API
checkPaperGeneratedRepo Paper-Server

paperVer=$(gethead Paper)
cd "$paper_dir/" || exit

bash ./paper patch

cd "Paper-Server" || exit
mcVer=$(mvn -o org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=minecraft_version | sed -n -e '/^\[.*\]/ !{ /^[0-9]/ { p; q } }')

basedir
. "$basedir"/scripts/importmcdev.sh

minecraftversion=$(grep <"$basedir"/Paper/work/BuildData/info.json minecraftVersion | cut -d '"' -f 4)
version=$(echo -e "Paper: $paperVer\nmc-dev:$importedmcdev")
tag="${minecraftversion}-${mcVer}-$(echo -e "$version" | shasum | awk '{print $1}')"
echo "$tag" >"$basedir"/current-paper

"$basedir"/scripts/generatesources.sh

cd Paper/ || exit

function tag() {
  (
    cd "$1" || exit
    if [ "$2" == "1" ]; then
      git tag -d "$tag" 2>/dev/null
    fi
    echo -e "$(date)\n\n$version" | git tag -a "$tag" -F - 2>/dev/null
  )
}
echo "Tagging as $tag"
echo -e "$version"

forcetag=0
if [ "$(cat "$basedir"/current-paper)" != "$tag" ]; then
  forcetag=1
fi

tag Paper-API $forcetag
tag Paper-Server $forcetag
