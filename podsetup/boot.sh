#!/usr/bin/env bash
# =====================================================================
#  Automatic pod setup: progress page + setup + Poser workflow + ComfyUI restart.
#
#  Two ways it gets started:
#   1) from the custom image: entry.sh runs it in the background at pod start (PODSETUP_SRC=/opt/podsetup)
#   2) by hand with one line in the Jupyter terminal (it downloads its own files from GitHub):
#        PODSETUP_RAW=https://raw.githubusercontent.com/<you>/<repo>/main/podsetup bash -c "$(curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/podsetup/boot.sh)"
#
#  Open the progress page from the pod's Connect tab (HTTP port 3000) to watch it.
# =====================================================================
set -u

D="${PODSETUP_DIR:-/workspace/podsetup}"
SRC="${PODSETUP_SRC:-}"           # folder that already holds the files (image mode); empty = download from GitHub
RAW="${PODSETUP_RAW:-}"           # base address of the podsetup folder on GitHub (needed when SRC is empty)
COMFY=/workspace/runpod-slim/ComfyUI
export PODSETUP_DIR="$D" PODSETUP_UNDER_BOOT=1

mkdir -p "$D"
echo "[boot] started $(date)"

stage() {
  printf '{"state":"%s","step":"%s","message":"%s","time":%s}\n' "$1" "$2" "$3" "$(date +%s)" > "$D/stage.json.tmp" \
    && mv "$D/stage.json.tmp" "$D/stage.json"
}
stage running waiting "Waiting for ComfyUI to start"

# ---- get the files ----
for f in progress_server.py progress.html setup.sh Poser.json; do
  if [ -n "$SRC" ]; then
    cp "$SRC/$f" "$D/$f" || echo "[boot] could not copy $f"
  elif [ -n "$RAW" ]; then
    curl -fsSL "$RAW/$f" -o "$D/$f" || echo "[boot] could not download $f"
  else
    echo "[boot] no PODSETUP_SRC or PODSETUP_RAW set, cannot get $f"
  fi
done
chmod +x "$D/setup.sh" 2>/dev/null

# ---- start the progress page (port 3000) once ----
if ! pgrep -f progress_server.py >/dev/null 2>&1; then
  nohup python3 "$D/progress_server.py" > "$D/progress_server.log" 2>&1 &
  echo "[boot] progress page started on port 3000"
fi

# ---- wait until the template has put ComfyUI in place and it answers on port 8188 ----
comfy_up() { curl -fs -o /dev/null --max-time 2 http://127.0.0.1:8188/; }
for i in $(seq 1 200); do
  [ -f "$COMFY/main.py" ] && comfy_up && break
  sleep 3
done

# ---- the real work ----
bash "$D/setup.sh"

# ---- put the Poser workflow into ComfyUI's workflow list ----
WF="$COMFY/user/default/workflows"
if [ -f "$D/Poser.json" ]; then
  mkdir -p "$WF" && cp "$D/Poser.json" "$WF/Poser.json" && echo "[boot] Poser workflow installed"
fi

# ---- restart ComfyUI so it loads the new nodes, and VERIFY that it really did ----
# Last time the Manager restart call did nothing and ComfyUI kept running with the old node list, while this script
# still reported success. So now we check the real result: a node from the new packs (Krea2EditModelPatch) and the
# res_2s sampler (RES4LYF) must show up in ComfyUI's own node list.
nodes_loaded() {
  curl -fs -m 15 http://127.0.0.1:8188/object_info/Krea2EditModelPatch 2>/dev/null | grep -q '"Krea2EditModelPatch"'     && curl -fs -m 15 http://127.0.0.1:8188/object_info/KSampler 2>/dev/null | grep -q 'res_2s'
}
wait_for_nodes() {   # wait up to $1 seconds for the new nodes to show up
  local t=0
  while [ "$t" -lt "$1" ]; do nodes_loaded && return 0; sleep 3; t=$((t+3)); done
  return 1
}
restart_direct() {   # fallback: stop the running ComfyUI and start it again with the same command, folder and environment
  local pid args=() envs=() cwd i
  pid=$(pgrep -f 'main\.py.*8188' | head -1)
  [ -n "$pid" ] || { echo "[boot] direct restart: no ComfyUI process found"; return 1; }
  cwd=$(readlink "/proc/$pid/cwd") || return 1
  mapfile -d '' -t args < "/proc/$pid/cmdline"
  mapfile -d '' -t envs < "/proc/$pid/environ"
  case "${args[0]:-}" in *python*) ;; *) echo "[boot] direct restart: unexpected command ${args[0]:-?}"; return 1;; esac
  echo "[boot] direct restart: stopping pid $pid, starting again: ${args[*]}"
  kill "$pid" 2>/dev/null
  for i in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill -9 "$pid" 2>/dev/null
  ( cd "$cwd" && nohup setsid env -i "${envs[@]}" "${args[@]}" >> "$D/comfyui-restart.log" 2>&1 & )
}

stage running restarting "Restarting ComfyUI so it loads the new nodes"
if nodes_loaded; then
  echo "[boot] the new nodes are already loaded, no restart needed"
else
  # attempt 1: the same thing Manager's Restart button does
  if ! curl -fs -m 10 http://127.0.0.1:8188/manager/reboot >/dev/null 2>&1; then
    curl -fs -m 10 http://127.0.0.1:8188/api/manager/reboot >/dev/null 2>&1 || echo "[boot] Manager restart call failed"
  fi
  if wait_for_nodes 120; then
    echo "[boot] ComfyUI restarted through Manager and the new nodes are loaded"
  else
    # attempt 2: restart it ourselves
    echo "[boot] Manager restart did not load the new nodes, trying a direct restart"
    stage running restarting "Restarting ComfyUI a second way"
    restart_direct
    if wait_for_nodes 180; then
      echo "[boot] ComfyUI restarted directly and the new nodes are loaded"
    else
      echo "[boot] ComfyUI still does not show the new nodes"
      echo "ComfyUI did not restart by itself. In ComfyUI click Manager, then Restart, then reload the page" >> "$D/failures.txt"
    fi
  fi
fi
for i in $(seq 1 100); do comfy_up && break; sleep 3; done

if [ -s "$D/failures.txt" ]; then
  stage problems finished "Finished, but some things did not install"
else
  stage ready finished "All set. ComfyUI is ready"
fi
echo "[boot] finished $(date)"
