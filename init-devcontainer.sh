#!/bin/bash

init_pre_commits(){
    # Install pre-commit for all iworx modules that contain
    # a ".pre-commit-config.yaml" file at its root.
    num_paths=0

    west list -f {path} | grep iworx | 
    while read prj_path; do
        # Check if pre-commit hook already exists
        if [ ! -s "$PRJ_ROOT_DIR/$prj_path/.git/hooks/pre-commit" ]; then
            # Check if directory contains a pre-commit config
            if [ -s "$PRJ_ROOT_DIR/$prj_path/.pre-commit-config.yaml" ]; then
                if [ $num_paths -eq 0 ]; then
                    # Print message and separator
                    echo "--------------------------------------------------"
                    echo "Setting up pre-commits"
                fi

                # Setup pre-commit
                cd "$PRJ_ROOT_DIR/$prj_path"
                echo "Installing to: $PRJ_ROOT_DIR/$prj_path"
                pre-commit install
                
                # increment the number of paths processed
                ((num_paths+=1))
            fi
        fi
    done

    if [ ! $num_paths -eq 0 ]; then
        echo "Pre-commits are setup"
    fi
}

init_west(){
    # Make sure app folder exists
    if [ ! -d "${APP_DIR}" ]; then
        echo "Unable to init west because APP_DIR:${APP_DIR} does not exist."
    else
        # Initialize West
        west init -l "${APP_DIR}" \
        && west config manifest.group-filter -- [+babblesim,+iworx] \
        && west config manifest.project-filter -- +nanopb

        # Build net tools if they exist
        if [ -d $NET_TOOLS_BASE ]; then
            cd $NET_TOOLS_BASE && make && cd "${PRJ_ROOT_DIR}"
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
    west update

    init_pre_commits
else
    echo "Unable to init devcontainer because PRJ_ROOT_DIR:${PRJ_ROOT_DIR} does not exist"
fi
