#!/bin/sh
# Copies the conformance vectors from enclavekit-anchor.
# Run after `cargo run -p gen-vectors` over there, then commit the copy.

set -eu
src="${1:-../enclavekit-anchor}"
cp "$src"/vectors/*.json Tests/EnclaveKitTests/Vectors/
git --no-pager -C "$src" log -1 --format='chore(vectors): pull from enclavekit-anchor %h' -- vectors