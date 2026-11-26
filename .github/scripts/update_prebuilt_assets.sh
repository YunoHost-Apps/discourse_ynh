#!/usr/bin/env bash
# Points the prebuilt_assets source in manifest.toml at the discourse-assets release matching the main source's tag.
# Needs gh, authenticated or with GH_TOKEN set. Run from the repository root.

set -euo pipefail

manifest="manifest.toml"

# Prints the value of a key inside one [resources.sources.<name>] block of the manifest
source_value() {
    sed -n "/^\s*\[resources\.sources\.$1\]/,/^\s*\[/ s/^\s*$2 = \"\(.*\)\"/\1/p" "$manifest"
}

# Replaces the value of a key inside one [resources.sources.<name>] block of the manifest
set_source_value() {
    sed -i "/^\s*\[resources\.sources\.$1\]/,/^\s*\[/ s|^\(\s*$2 = \"\).*\"|\1$3\"|" "$manifest"
}

main_url=$(source_value main url)
tag=$(sed -n 's|.*/archive/refs/tags/\(v[^/]*\)\.tar\.gz$|\1|p' <<< "$main_url")
if [ -z "$tag" ]; then
    echo "Cannot read a tag from the main source url: $main_url" >&2
    exit 1
fi

commit=$(gh api "repos/discourse/discourse/commits/$tag" --jq .sha)
release="$tag-${commit:0:8}"

if ! asset=$(gh api "repos/discourse/discourse-assets/releases/tags/$release" \
        --jq '.assets[] | select(.name == "production.tar.gz") | "\(.browser_download_url) \(.digest)"' 2>/dev/null) \
    || [ -z "$asset" ]; then
    echo "No production.tar.gz in discourse-assets release $release yet, try again later" >&2
    exit 1
fi

url=${asset%% *}
sha256=${asset##* sha256:}

if [ "$(source_value prebuilt_assets url)" = "$url" ] && [ "$(source_value prebuilt_assets sha256)" = "$sha256" ]; then
    echo "prebuilt_assets already points at $release"
    exit 0
fi

set_source_value prebuilt_assets url "$url"
set_source_value prebuilt_assets sha256 "$sha256"
echo "prebuilt_assets updated to $release"
