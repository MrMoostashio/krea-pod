#!/bin/bash
# Entrypoint of the custom image. Starts our automatic setup in the background, then hands over to the
# official template's own start script exactly as before, so ComfyUI, Jupyter and FileBrowser start normally.
mkdir -p /workspace/podsetup
( PODSETUP_SRC=/opt/podsetup bash /opt/podsetup/boot.sh > /workspace/podsetup/boot.log 2>&1 ) &
exec /start.sh "$@"
