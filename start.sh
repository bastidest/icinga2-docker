#!/bin/bash
set -e
set -o pipefail

source ./source.sh

compose() {
    local args=("$@")
    docker-compose -f docker-compose.full.yml ${args}
}

args=("$@")

if [ -z "$1" ]; then
    compose pull
    compose up
else
    compose "$@"
fi
