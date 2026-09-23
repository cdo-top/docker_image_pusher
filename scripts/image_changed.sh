#!/usr/bin/env bash

# Exit codes: 0 unchanged, 1 changed/missing, 2 inspection failure.
inspect_manifest() {
    local reference="$1" cache_file=""
    if [[ -n "${MANIFEST_CACHE_DIR:-}" ]]; then
        mkdir -p "$MANIFEST_CACHE_DIR"
        cache_file="$MANIFEST_CACHE_DIR/$(printf '%s' "$reference" | sha256sum | awk '{print $1}').json"
        if [[ -s "$cache_file" ]]; then
            cat "$cache_file"
            return
        fi
    fi
    local manifest
    manifest=$(timeout --kill-after=5s "${MANIFEST_TIMEOUT_SECONDS:-60}s" \
        docker buildx imagetools inspect --raw "$reference") || return
    if [[ -n "$cache_file" ]]; then
        printf '%s' "$manifest" > "$cache_file"
    fi
    printf '%s\n' "$manifest"
}

content_signature() {
    jq -ceS '{config: .config.digest, layers: [.layers[].digest]} |
        if (.config | type) == "string" and all(.layers[]; type == "string")
        then . else error("Invalid image manifest") end'
}

platform_contents() {
    local reference="$1" manifest="$2" platforms="$3"
    local entries entry child signature contents='[]'
    if ! jq -e 'has("manifests")' <<< "$manifest" >/dev/null; then
        signature=$(content_signature <<< "$manifest") || return 2
        jq -cn --argjson content "$signature" '[{platform: "single", content: $content}]'
        return
    fi
    entries=$(jq -ce --argjson platforms "$platforms" '
        [.manifests[] | select(
            (.platform.os + "/" + .platform.architecture) as $name |
            $platforms | index($name)) |
            {digest, platform: (.platform.os + "/" + .platform.architecture)}]' <<< "$manifest") || return 2
    while IFS= read -r entry; do
        echo ">>> inspect platform manifest: $reference $(jq -r '.platform' <<< "$entry")" >&2
        child=$(inspect_manifest "${reference%%@*}@$(jq -r '.digest' <<< "$entry")") || return 2
        signature=$(content_signature <<< "$child") || return 2
        contents=$(jq -c --argjson entry "$entry" --argjson content "$signature" \
            '. + [{platform: $entry.platform, content: $content}]' <<< "$contents") || return 2
    done < <(jq -c '.[]' <<< "$entries")
    jq -cS 'sort_by(.platform)' <<< "$contents"
}

image_changed() {
    local source="$1" target="$2"
    shift 2
    local platforms source_manifest target_manifest source_contents target_contents
    platforms=$(jq -cn --args '$ARGS.positional' "$@") || return 2
    echo ">>> inspect source: $source" >&2
    source_manifest=$(inspect_manifest "$source") || {
        echo "ERROR: Source inspection failed or timed out: $source" >&2
        return 2
    }
    source_contents=$(platform_contents "$source" "$source_manifest" "$platforms") || return 2
    if [[ "$source_contents" == '[]' ]]; then
        echo "ERROR: No requested platforms found in $source" >&2
        return 2
    fi
    echo ">>> inspect target: $target" >&2
    if ! target_manifest=$(inspect_manifest "$target" 2>&1); then
        if grep -Eqi 'manifest unknown|name unknown|404 Not Found|: not found([[:space:]]|$)' <<< "$target_manifest"; then
            echo ">>> target missing: $target" >&2
            return 1
        fi
        echo "ERROR: Cannot inspect $target: $target_manifest" >&2
        return 2
    fi
    target_contents=$(platform_contents "$target" "$target_manifest" "$platforms") || return 2
    if jq -e '.[0].platform == "single"' <<< "$source_contents" >/dev/null ||
       jq -e '.[0].platform == "single"' <<< "$target_contents" >/dev/null; then
        source_contents=$(jq -cS 'map(.content)' <<< "$source_contents") || return 2
        target_contents=$(jq -cS 'map(.content)' <<< "$target_contents") || return 2
    fi
    if [[ "$source_contents" == "$target_contents" ]]; then
        echo ">>> contents unchanged: $source -> $target" >&2
        return 0
    fi
    echo ">>> contents changed: $source -> $target" >&2
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -o pipefail
    command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 2; }
    command -v timeout >/dev/null || { echo "ERROR: timeout is required" >&2; exit 2; }
    image_changed "$@"
fi
