#!/usr/bin/env bash
# =====================================================================
#  Lean ComfyUI pod setup for Krea 2 - Image, Dataset, Edit and Poser workflows
#  Works two ways:
#   - by hand: paste/run it in the pod's terminal (safe to run again; finished downloads are skipped)
#   - automatically: boot.sh runs it and the progress page (port 3000) shows what it is doing
#
#  Needs (optional) env var CIVITAI_API_KEY for the 4 CivitAI LoRAs.
#  The key is never printed or written to any file.
# =====================================================================
set -u

CIVITAI_HOST="${CIVITAI_HOST:-civitai.com}"   # if CivitAI downloads fail with 401/403/404, retry with: CIVITAI_HOST=civitai.red bash setup.sh
UPDATE_COMFY="${UPDATE_COMFY:-1}"             # 1 = update ComfyUI first. 0 = leave it alone.
MAXJOBS=4                                     # downloads running at the same time
PODSETUP_DIR="${PODSETUP_DIR:-/workspace/podsetup}"   # progress information for the progress page lives here

# ---------------------------------------------------------------------
#  EDIT THESE LISTS TO ADD OR REMOVE THINGS
# ---------------------------------------------------------------------
# Models:  <folder inside ComfyUI/models> | <filename to save as> | <source> | <approximate size in MB, for the progress bar>
#   source = a direct URL, or  civitai:<version id>  (uses your CIVITAI_API_KEY)
HF="https://huggingface.co"
MODELS=(
  # --- core (all workflows) ---
  "diffusion_models|krea2_turbo_fp8_scaled.safetensors|$HF/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors|12800"
  "text_encoders|qwen3vl_4b_fp8_scaled.safetensors|$HF/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors|5000"
  "vae|qwen_image_vae.safetensors|$HF/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors|243"
  # --- Image workflow extras ---
  "upscale_models|4xNMKDSuperscale_4xNMKDSuperscale.pt|$HF/alexgenovese/upscalers/resolve/main/4xNMKDSuperscale_4xNMKDSuperscale.pt|64"
  "ultralytics/bbox|face_yolov8m.pt|$HF/Bingsu/adetailer/resolve/main/face_yolov8m.pt|50"
  "sams|sam_vit_b_01ec64.pth|https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth|358"
  # --- LoRAs: public Hugging Face mirror, no account needed ---
  "loras|famegrid_spicy.safetensors|$HF/Alex995647/loras-krea-2/resolve/main/famegrid-krea-2-z-image-qwen-realism-lora/famegrid_spicy.safetensors|1550"
  "loras|krea2_identity_edit_v1_2.safetensors|$HF/Alex995647/loras-krea-2/resolve/main/krea-2-identity-edit/krea2_identity_edit_v1_2.safetensors|1850"
  "loras|ass_v2_krea2_loraholic.safetensors|$HF/Alex995647/loras-krea-2/resolve/main/ass-and-thighs-slider-krea-2-zit/ass_v2_krea2_loraholic.safetensors|48"
  # --- LoRAs: CivitAI (need CIVITAI_API_KEY) ---
  "loras|krea2-bloomgirls-realism-step00004000.safetensors|civitai:3191538|448"
  "loras|MysticXXX_KREA2_v1.safetensors|civitai:3067313|218"
  "loras|snofs_krea_v1_4.safetensors|civitai:3290120|1520"
  "loras|breast_size_v2_krea2_loraholic.safetensors|civitai:3131773|35"
)

# Custom node packs (GitHub repos, cloned into ComfyUI/custom_nodes)
NODES=(
  "https://github.com/lbouaraba/comfyui-krea2edit"
  "https://github.com/kijai/ComfyUI-KJNodes"
  "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes"
  "https://github.com/rgthree/rgthree-comfy"
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
  "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
  "https://github.com/ClownsharkBatwing/RES4LYF"   # adds the res_2s sampler that the Poser/Dataset workflows use
)
# ---------------------------------------------------------------------

mkdir -p "$PODSETUP_DIR"
LOG=/workspace/setup.log
[ -d /workspace ] || LOG=/tmp/setup.log
exec > >(tee -a "$LOG") 2>&1
echo "=== setup started $(date) ==="

# progress reporting for the progress page: stage <state> <step> <message>   (messages must not contain quotes)
stage() {
  printf '{"state":"%s","step":"%s","message":"%s","time":%s}\n' "$1" "$2" "$3" "$(date +%s)" > "$PODSETUP_DIR/stage.json.tmp" \
    && mv "$PODSETUP_DIR/stage.json.tmp" "$PODSETUP_DIR/stage.json"
}
stage running starting "Getting ready"

# ---- find ComfyUI ----
COMFY=""
for d in /workspace/runpod-slim/ComfyUI /workspace/ComfyUI /ComfyUI /opt/ComfyUI /app/ComfyUI /root/ComfyUI; do
  if [ -f "$d/main.py" ]; then COMFY="$d"; break; fi
done
if [ -z "$COMFY" ]; then
  f=$(find / -maxdepth 5 -name main.py -path "*ComfyUI/main.py" -not -path "*/custom_nodes/*" 2>/dev/null | head -1)
  [ -n "$f" ] && COMFY=$(dirname "$f")
fi
if [ -z "$COMFY" ]; then
  echo "ERROR: could not find ComfyUI on this pod. Is this the ComfyUI template?"
  stage failed nocomfy "Could not find ComfyUI on this pod"
  exit 1
fi
echo "ComfyUI folder: $COMFY"
MODELS_DIR="$COMFY/models"

# ---- find the python ComfyUI uses ----
PY=python3
# RunPod's official ComfyUI template keeps its venv inside the ComfyUI folder, named like .venv-cu128
for p in "$COMFY"/.venv-cu*/bin/python "$COMFY/.venv/bin/python" "$COMFY/venv/bin/python" "$COMFY/../venv/bin/python" "/workspace/venv/bin/python"; do
  if [ -x "$p" ]; then PY="$p"; break; fi
done
echo "Python: $PY"

# ---- write the plan the progress page reads (which files and node packs to expect) ----
rm -rf "$PODSETUP_DIR/nodes"; mkdir -p "$PODSETUP_DIR/nodes"
plan='{"files":['; first=1
for entry in "${MODELS[@]}"; do
  IFS='|' read -r sub name src mb <<< "$entry"
  [ "$first" = 1 ] || plan+=","; first=0
  plan+="{\"name\":\"$name\",\"sub\":\"$sub\",\"path\":\"$MODELS_DIR/$sub/$name\",\"mb\":${mb:-0}}"
done
plan+='],"nodes":['; first=1
for url in "${NODES[@]}"; do
  [ "$first" = 1 ] || plan+=","; first=0
  plan+="\"$(basename "$url")\""
done
plan+=']}'
printf '%s\n' "$plan" > "$PODSETUP_DIR/plan.json"

# ---- downloader ----
if ! command -v aria2c >/dev/null 2>&1; then
  (apt-get update -qq && apt-get install -y -qq aria2) >/dev/null 2>&1 || echo "note: could not install aria2, using curl (slower)"
fi

FAILS="$PODSETUP_DIR/failures.txt"; : > "$FAILS"

dl_one() {
  local sub="$1" name="$2" src="$3"
  local dir="$MODELS_DIR/$sub"
  local out="$dir/$name"
  local tmp="$out.part"
  mkdir -p "$dir"
  if [ -f "$out" ] && [ "$(stat -c%s "$out")" -gt 1000000 ]; then
    echo "[have]  $name"; return 0
  fi
  rm -f "$tmp"
  echo "[start] $name"
  if [[ "$src" == civitai:* ]]; then
    if [ -z "${CIVITAI_API_KEY:-}" ]; then
      echo "[SKIP]  $name - CIVITAI_API_KEY is not set"; echo "$name (no CivitAI key)" >> "$FAILS"; return 1
    fi
    local id="${src#civitai:}" code
    code=$(curl -sSL -H "Authorization: Bearer $CIVITAI_API_KEY" -o "$tmp" -w "%{http_code}" \
           "https://$CIVITAI_HOST/api/download/models/$id?type=Model&format=SafeTensor")
    if [ "$code" != "200" ]; then
      echo "[FAIL]  $name - CivitAI answered HTTP $code (try CIVITAI_HOST=civitai.red, or check the key)"
      rm -f "$tmp"; echo "$name (CivitAI HTTP $code)" >> "$FAILS"; return 1
    fi
  else
    if command -v aria2c >/dev/null 2>&1; then
      aria2c -x16 -s16 -k4M -q --allow-overwrite=true -d "$dir" -o "$name.part" "$src" || { echo "[FAIL]  $name"; rm -f "$tmp"; echo "$name (download failed)" >> "$FAILS"; return 1; }
    else
      curl -sSL --fail -o "$tmp" "$src" || { echo "[FAIL]  $name"; rm -f "$tmp"; echo "$name (download failed)" >> "$FAILS"; return 1; }
    fi
  fi
  if [ ! -f "$tmp" ] || [ "$(stat -c%s "$tmp")" -lt 1000000 ]; then
    echo "[FAIL]  $name - file missing or too small"; rm -f "$tmp"; echo "$name (bad file)" >> "$FAILS"; return 1
  fi
  mv "$tmp" "$out"
  echo "[done]  $name ($(du -h "$out" | cut -f1))"
}

# ---- 1) update ComfyUI ----
if [ "$UPDATE_COMFY" = "1" ] && [ -d "$COMFY/.git" ]; then
  stage running updating "Updating ComfyUI"
  echo "--- updating ComfyUI ---"
  # the template's ComfyUI checkout has no upstream set, so name the remote and the current branch explicitly
  BR=$(git -C "$COMFY" rev-parse --abbrev-ref HEAD 2>/dev/null)
  git -C "$COMFY" pull --ff-only origin "${BR:-master}" || echo "note: ComfyUI update skipped (local changes or no network)"
  "$PY" -m pip install -q -r "$COMFY/requirements.txt" || echo "note: requirements install had a problem"
fi

# ---- 2) start the model downloads in the background (core files first) ----
stage running working "Downloading models and installing extra nodes"
echo "--- downloading models ---"
DL_PIDS=()
for entry in "${MODELS[@]}"; do
  IFS='|' read -r sub name src mb <<< "$entry"
  while [ "$(jobs -rp | wc -l)" -ge "$MAXJOBS" ]; do wait -n 2>/dev/null || sleep 1; done
  dl_one "$sub" "$name" "$src" &
  DL_PIDS+=($!)
done

# ---- 3) install custom nodes while downloads run ----
echo "--- installing custom nodes ---"
mkdir -p "$COMFY/custom_nodes"
for url in "${NODES[@]}"; do
  n=$(basename "$url")
  if [ ! -d "$COMFY/custom_nodes/$n" ]; then
    git clone --depth 1 -q "$url" "$COMFY/custom_nodes/$n" || { echo "[FAIL]  node pack $n"; echo "node pack $n (could not download)" >> "$FAILS"; continue; }
  fi
  [ -f "$COMFY/custom_nodes/$n/requirements.txt" ] && "$PY" -m pip install -q -r "$COMFY/custom_nodes/$n/requirements.txt" || true
  [ -f "$COMFY/custom_nodes/$n/install.py" ] && (cd "$COMFY/custom_nodes/$n" && "$PY" install.py) >/dev/null 2>&1 || true
  touch "$PODSETUP_DIR/nodes/$n.done"
  echo "[node]  $n"
done

# wait only for the download jobs. (A bare "wait" can hang here, because it can also wait on the logging process.)
for p in "${DL_PIDS[@]}"; do wait "$p" 2>/dev/null || true; done

echo
echo "=================== SUMMARY ==================="
if [ -s "$FAILS" ]; then
  echo "These did NOT finish:"; sed 's/^/  - /' "$FAILS"
  echo "Fix the cause, then run this script again. It skips what is already downloaded."
  stage problems finished "Finished, but some things did not install"
else
  echo "Everything downloaded and installed."
  stage installed finished "All files downloaded and nodes installed"
fi
echo "Log: $LOG"
if [ -z "${PODSETUP_UNDER_BOOT:-}" ]; then
  echo "NEXT: restart ComfyUI so it sees the new nodes (ComfyUI Manager > Restart), then reload the page and open your workflow."
fi
