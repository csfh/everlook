#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
addon="${root}/addon"
license="${root}/LICENSE"
core="${addon}/Everlook"
version="${1:-}"
outdir="${2:-$root/dist}"

if [[ -z "${version}" ]]; then
  version="$(awk -F': ' '/^## Version:/{gsub("\r","",$2); print $2; exit}' "${core}/Everlook.toc")"
fi

if [[ -z "${version}" ]]; then
  echo "Could not determine Everlook version from addon/Everlook/Everlook.toc" >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT
mkdir -p "${outdir}"

folders=()
for source in "${addon}"/Everlook "${addon}"/Everlook_*; do
  [[ -d "${source}" ]] || continue
  name="$(basename "${source}")"
  folders+=("${name}")
  while IFS= read -r -d '' file; do
    rel="${file#./}"
    dest="${stage}/${name}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    cp -a "${source}/${rel}" "${dest}"
  done < <(
    cd "${source}"
    find . -type f \
      \( -name '*.lua' -o -name '*.toc' -o -name '*.xml' -o -name '*.tga' -o -name '*.ttf' -o -name '*.txt' \) \
      -print0
  )
done

# The MIT license has to travel with every copy of the code.
if [[ ! -f "${license}" ]]; then
  echo "Missing LICENSE; the archive must carry it" >&2
  exit 1
fi
cp "${license}" "${stage}/Everlook/LICENSE"

# Module TOCs carry no version in the repository. Each release stamps the
# core's version into them so the addon list shows one version for the set.
for name in "${folders[@]}"; do
  [[ "${name}" == Everlook ]] && continue
  toc="${stage}/${name}/${name}.toc"
  awk -v version="${version}" '{ print } /^## Interface:/ { print "## Version: " version }' "${toc}" > "${toc}.stamped"
  mv "${toc}.stamped" "${toc}"
done

# The same commit packs to the same bytes: files are put in a fixed order with a fixed time, owner and mode,
# and no name or time goes into the gzip header. The time is the commit's (or SOURCE_DATE_EPOCH), not the clock.
epoch="${SOURCE_DATE_EPOCH:-$(git -C "${root}" log -1 --format=%ct 2>/dev/null || true)}"
epoch="${epoch:-315532800}"
find "${stage}" -type d -exec chmod 755 {} +
find "${stage}" -type f -exec chmod 644 {} +

archive="${outdir}/Everlook-${version}.tar.gz"
tar -C "${stage}" --sort=name --mtime="@${epoch}" --owner=0 --group=0 --numeric-owner -cf - "${folders[@]}" | gzip -n -9 > "${archive}"

# Windows opens a .zip without extra tools, so every release carries the same folders as one.
zip_archive="${outdir}/Everlook-${version}.zip"
python3 - "${stage}" "${zip_archive}" "${epoch}" "${folders[@]}" <<'PY'
import sys
import time
import zipfile
from pathlib import Path

stage, target, epoch, *folders = sys.argv[1:]
stamp = time.gmtime(max(int(epoch), 315532800))[:6]
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for folder in sorted(folders):
        for path in sorted(Path(stage, folder).rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(stage).as_posix(), stamp)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                archive.writestr(info, path.read_bytes())
PY

members="$(tar -tzf "${archive}")"
for name in "${folders[@]}"; do
  if ! grep -Fx "${name}/${name}.toc" <<<"${members}" >/dev/null; then
    echo "Packed archive is missing ${name}/${name}.toc" >&2
    exit 1
  fi
done

zip_members="$(python3 -c 'import sys, zipfile; print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))' "${zip_archive}")"
for name in "${folders[@]}"; do
  if ! grep -Fx "${name}/${name}.toc" <<<"${zip_members}" >/dev/null; then
    echo "Packed zip is missing ${name}/${name}.toc" >&2
    exit 1
  fi
done

# What was built, as checksums a player can check a download against.
(
  cd "${outdir}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "Everlook-${version}.tar.gz" "Everlook-${version}.zip" > SHA256SUMS
  else
    shasum -a 256 "Everlook-${version}.tar.gz" "Everlook-${version}.zip" > SHA256SUMS
  fi
)

echo "${archive}"
