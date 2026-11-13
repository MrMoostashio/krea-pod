#!/usr/bin/env bash
# =====================================================================
#  Lean ComfyUI pod setup for Krea 2 - Image, Dataset, Edit and Poser workflows
#  Works two ways:
#   - by hand: paste/run it in the pod's terminal (safe to run again; finished downloads are skipped)
#   - automatically: boot.sh runs it and the progress page (port 3000) shows what it is doing
#
#  POD_PROFILE=video (template env var) installs the Wan 2.2 Animate motion-control stack instead of the Krea 2 one.
#  Needs (optional) env var CIVITAI_API_KEY for the 4 CivitAI LoRAs (krea profile only).
#  The key is never printed or written to any file.
# =====================================================================
set -u

CIVITAI_HOST="${CIVITAI_HOST:-civitai.com}"   # if CivitAI downloads fail with 401/403/404, retry with: CIVITAI_HOST=civitai.red bash setup.sh
UPDATE_COMFY="${UPDATE_COMFY:-1}"             # 1 = update ComfyUI first. 0 = leave it alone.
MAXJOBS=4                                     # downloads running at the same time
PODSETUP_DIR="${PODSETUP_DIR:-/workspace/podsetup}"   # progress information for the progress page lives here
POD_PROFILE="${POD_PROFILE:-krea}"            # krea (default, the image workflows) or video (Wan 2.2 Animate motion control). Set it as a template environment variable.

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
#  VIDEO PROFILE (POD_PROFILE=video): replaces the two lists above.
#  Everything the "Motion Control GOD Edition" workflow loads (Wan 2.2 Animate 14B). About 62 GB of models.
#  The workflow file itself is NOT stored here: drag it into the ComfyUI page by hand.
# ---------------------------------------------------------------------
if [ "$POD_PROFILE" = "video" ]; then
MODELS=(
  "diffusion_models|wan2.2_animate_14B_bf16.safetensors|$HF/Comfy-Org/Wan-2.2/resolve/main/split_files/diffusion_models/wan2.2_animate_14B_bf16.safetensors|35400"
  "text_encoders|umt5_xxl_fp16.safetensors|$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors|11640"
  "vae|Wan2_1_VAE_bf16.safetensors|$HF/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors|254"
  "clip_vision|clip_vision_h.safetensors|$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors|1290"
  # --- pose, face and mask helpers ---
  "detection|vitpose_h_wholebody_model.onnx|$HF/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx|1"
  "detection|vitpose_h_wholebody_data.bin|$HF/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin|2600"
  "detection|yolov10m.onnx|$HF/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx|62"
  "sam2|sam2.1_hiera_base_plus.safetensors|$HF/Kijai/sam2-safetensors/resolve/main/sam2.1_hiera_base_plus.safetensors|323"
  # --- LoRAs used by the GOD workflow ---
  "loras|wan2.2_animate_14B_relight_lora_bf16.safetensors|$HF/Comfy-Org/Wan-2.2/resolve/main/split_files/loras/wan2.2_animate_14B_relight_lora_bf16.safetensors|1470"
  "loras|lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank256_bf16.safetensors|$HF/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank256_bf16.safetensors|2560"
  "loras|wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|$HF/Comfy-Org/Wan-2.2/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|1260"
  "loras|Wan21_PusaV1_LoRA_14B_rank512_bf16.safetensors|$HF/Kijai/WanVideo_comfy/resolve/main/Pusa/Wan21_PusaV1_LoRA_14B_rank512_bf16.safetensors|5030"
  # The workflow asks for Wan2.2-Fun-A14B-InP-low-noise-MPS.safetensors, which is not on Hugging Face under that name.
  # This is the closest public file (the Fun MPS reward LoRA, rank 22), saved under the name the workflow expects. It is a stand-in, not a verified copy.
  "loras|Wan2.2-Fun-A14B-InP-low-noise-MPS.safetensors|$HF/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_FunReward/Wan2.2-Fun-A14B-InP-LOW-MPS_resized_dynamic_avg_rank_22_bf16.safetensors|150"
)
# (rife49.pth is downloaded by the Frame-Interpolation node itself the first time it runs.)
NODES=(
  "https://github.com/kijai/ComfyUI-WanVideoWrapper"
  "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
  "https://github.com/kijai/ComfyUI-segment-anything-2"
  "https://github.com/kijai/ComfyUI-KJNodes"
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
  "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation"
  "https://github.com/yolain/ComfyUI-Easy-Use"
  "https://github.com/evanspearman/ComfyMath"
  "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
  "https://github.com/rgthree/rgthree-comfy"
)
fi
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

# ---- optional: character LoRAs from a PRIVATE Hugging Face repo ----
# Set these as RunPod template environment variables / secrets (never put them in this repository):
#   HF_TOKEN       a READ-ONLY Hugging Face token
#   HF_LORA_REPO   the private model repo, as  name/repo
#   HF_LORA_MATCH  optional regex on the file path, e.g. "jade" to fetch only Jade's checkpoints (default: every .safetensors in the repo)
# If these are not set, this section does nothing.
HF_ERR=""
if [ "$POD_PROFILE" = "krea" ] && [ -n "${HF_TOKEN:-}" ] && [ -n "${HF_LORA_REPO:-}" ]; then
  echo "--- looking up LoRAs in the private Hugging Face repo ---"
  HF_LIST=$(HF_TOKEN="$HF_TOKEN" HF_LORA_REPO="$HF_LORA_REPO" HF_LORA_MATCH="${HF_LORA_MATCH:-}" "$PY" - <<'PYEOF' 2>/dev/null
import os, re, json, urllib.request
repo = os.environ["HF_LORA_REPO"]; pat = os.environ.get("HF_LORA_MATCH") or "."
req = urllib.request.Request("https://huggingface.co/api/models/%s/tree/main?recursive=true" % repo,
                             headers={"Authorization": "Bearer " + os.environ["HF_TOKEN"]})
items = json.load(urllib.request.urlopen(req, timeout=60))
for it in items:
    path = it.get("path", "")
    if it.get("type") == "file" and path.endswith(".safetensors") and re.search(pat, path):
        print("%s	%d" % (path, max(1, int(it.get("size", 0)) // 1048576)))
PYEOF
  ) || HF_LIST=""
  if [ -z "$HF_LIST" ]; then
    HF_ERR="Hugging Face LoRAs (no files found - check HF_TOKEN, HF_LORA_REPO and HF_LORA_MATCH)"
    echo "note: $HF_ERR"
  else
    while IFS=$'	' read -r hfpath hfmb; do
      [ -n "$hfpath" ] && MODELS+=("loras|$(basename "$hfpath")|hfprivate:${HF_LORA_REPO}::${hfpath}|${hfmb}")
    done <<< "$HF_LIST"
    echo "found $(echo "$HF_LIST" | wc -l) LoRA file(s) to download"
  fi
fi

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
[ -n "${HF_ERR:-}" ] && echo "$HF_ERR" >> "$FAILS"

dl_one() {
  local sub="$1" name="$2" src="$3"
  local dir="$MODELS_DIR/$sub"
  local out="$dir/$name"
  local tmp="$out.part"
  mkdir -p "$dir"
  if [ -f "$out" ] && [ "$(stat -c%s "$out")" -gt 100000 ]; then
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
  elif [[ "$src" == hfprivate:* ]]; then
    if [ -z "${HF_TOKEN:-}" ]; then
      echo "[SKIP]  $name - HF_TOKEN is not set"; echo "$name (no Hugging Face token)" >> "$FAILS"; return 1
    fi
    local spec="${src#hfprivate:}" hfrepo hfpath hfcode
    hfrepo="${spec%%::*}"; hfpath="${spec#*::}"
    hfcode=$(curl -sSL -H "Authorization: Bearer $HF_TOKEN" -o "$tmp" -w "%{http_code}" "https://huggingface.co/$hfrepo/resolve/main/$hfpath")
    if [ "$hfcode" != "200" ]; then
      echo "[FAIL]  $name - Hugging Face answered HTTP $hfcode (check the token and repo name)"
      rm -f "$tmp"; echo "$name (Hugging Face HTTP $hfcode)" >> "$FAILS"; return 1
    fi
  else
    if command -v aria2c >/dev/null 2>&1; then
      aria2c -x16 -s16 -k4M -q --allow-overwrite=true -d "$dir" -o "$name.part" "$src" || { echo "[FAIL]  $name"; rm -f "$tmp"; echo "$name (download failed)" >> "$FAILS"; return 1; }
    else
      curl -sSL --fail -o "$tmp" "$src" || { echo "[FAIL]  $name"; rm -f "$tmp"; echo "$name (download failed)" >> "$FAILS"; return 1; }
    fi
  fi
  if [ ! -f "$tmp" ] || [ "$(stat -c%s "$tmp")" -lt 100000 ]; then
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
