#!/usr/bin/env bash

init_pre_commits() {
    local num_paths=0
    local -a pre_commit_cmd

    if python3 -c 'import pre_commit' >/dev/null 2>&1; then
        pre_commit_cmd=(python3 -m pre_commit)
    elif command -v pre-commit >/dev/null 2>&1; then
        pre_commit_cmd=(pre-commit)
    else
        echo "Skipping pre-commit setup because pre-commit is not installed"
        return 0
    fi

    while IFS= read -r prj_path; do
        local repo_path="$PRJ_ROOT_DIR/$prj_path"

        if [ ! -s "$repo_path/.pre-commit-config.yaml" ]; then
            continue
        fi

        if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
            continue
        fi

        if [ "$num_paths" -eq 0 ]; then
            echo "--------------------------------------------------"
            echo "Setting up pre-commits"
        fi

        echo "Installing to: $repo_path"
        (
            cd "$repo_path" || exit 1
            "${pre_commit_cmd[@]}" install
        )

        num_paths=$((num_paths + 1))
    done < <(west list -f '{path}' | grep iworx)

    if [ "$num_paths" -ne 0 ]; then
        echo "Pre-commits are setup"
    fi
}

init_west(){
    # Make sure app folder exists
    if [ ! -d "${APPS_DIR}" ]; then
        echo "Unable to init west because APPS_DIR:${APPS_DIR} does not exist."
    else
        # Initialize West
        west init -l "${APPS_DIR}" \
            && west config manifest.project-filter -- +nanopb

        if [ -d "$NET_TOOLS_BASE" ]; then
            cd "$NET_TOOLS_BASE" && make && cd "${PRJ_ROOT_DIR}"
        fi
    fi
}

# Check that PRJ_ROOT_DIR exists
if [ -d "${PRJ_ROOT_DIR}" ]; then
    cd "${PRJ_ROOT_DIR}"
    # .west directory won't exist if west isn't initialized
    if [ ! -d .west ]; then
        init_west
    fi
    # Check for updates in manifest
    west update -r
    init_pre_commits
else
    echo "Unable to init devcontainer because PRJ_ROOT_DIR:${PRJ_ROOT_DIR} does not exist"
fi