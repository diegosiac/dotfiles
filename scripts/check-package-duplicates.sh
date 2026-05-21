#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

awk '
    {
        line = $0
        sub(/[[:space:]]*#.*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    }
    line == "" { next }
    {
        count[line]++
        if (files[line] == "") {
            files[line] = FILENAME
        } else if (files[line] !~ "(^|, )" FILENAME "(, |$)") {
            files[line] = files[line] ", " FILENAME
        }
    }
    END {
        for (package in count) {
            if (count[package] > 1) {
                duplicates[package] = files[package]
                found = 1
            }
        }

        if (!found) {
            print "OK"
            exit 0
        }

        print "Duplicate packages:"
        for (package in duplicates) {
            printf "%s: %s\n", package, duplicates[package]
        }
        exit 1
    }
' \
    "$repo_root"/packages/arch/*.txt
