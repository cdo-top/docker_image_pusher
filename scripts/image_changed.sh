#!/usr/bin/env bash

# Exit codes: 0 unchanged, 1 changed/missing, 2 inspection failure.
inspect_manifest() {
    docker buildx imagetools inspect --raw "$1"
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
            {digest, platform: (.platform.os + "/" + .platform.architecture +
                "/" + (.platform.variant // ""))}]' <<< "$manifest") || return 2
    while IFS= read -r entry; do
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
    source_manifest=$(inspect_manifest "$source") || return 2
    source_contents=$(platform_contents "$source" "$source_manifest" "$platforms") || return 2
    if [[ "$source_contents" == '[]' ]]; then
        echo "ERROR: No requested platforms found in $source" >&2
        return 2
    fi
    if ! target_manifest=$(inspect_manifest "$target" 2>&1); then
        if grep -Eqi 'manifest unknown|name unknown|not found' <<< "$target_manifest"; then
            return 1
        fi
        echo "ERROR: Cannot inspect $target: $target_manifest" >&2
        return 2
    fi
    target_contents=$(platform_contents "$target" "$target_manifest" "$platforms") || return 2
    if jq -e '.[0].platform == "single"' <<< "$source_contents" >/dev/null; then
        source_contents=$(jq -cS 'map(.content)' <<< "$source_contents") || return 2
        target_contents=$(jq -cS 'map(.content)' <<< "$target_contents") || return 2
    fi
    [[ "$source_contents" == "$target_contents" ]] && return 0
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -o pipefail
    command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 2; }
    image_changed "$@"
fi
