# Krea pod setup

Automatic setup for a RunPod pod running ComfyUI with Krea 2. When a pod starts, a progress page (port 3000) shows
what is happening ("Downloading LoRAs...", "Installing extra nodes...", "Restarting ComfyUI..."), and when it is done
there is an **Open ComfyUI** button. The Poser workflow is already in ComfyUI's workflow list.

There are no secrets in this repository. Your CivitAI key stays in your RunPod secret (`CIVITAI_API_KEY`).

## What is in here

- `podsetup/boot.sh` runs everything in order: progress page, setup, Poser workflow, ComfyUI restart.
- `podsetup/setup.sh` downloads the models and LoRAs and installs the node packs. **Edit the lists at the top to add or remove things.**
- `podsetup/progress_server.py` and `podsetup/progress.html` are the progress page.
- `podsetup/Poser.json` is the Poser workflow.
- `podsetup/Reference.json` is the Reference workflow (a copy of Poser for making reference portraits and full-body photos). Both workflows are installed into ComfyUI's workflow list on every new pod.
- `podsetup/entry.sh`, `Dockerfile` and `.github/workflows/build-image.yml` build the custom pod image (Option A below).

## Option A (fully automatic): a custom image that GitHub builds for you

1. Make a free GitHub account, then click **New repository**. Name it `krea-pod`. Public is simplest (see "Public or private" below).
2. On the new repository page click **uploading an existing file** and drag in everything from this folder:
   `README.md`, `Dockerfile`, the `podsetup` folder and the `.github` folder. Click **Commit changes**.
3. Click the **Actions** tab. A job called **Build pod image** starts by itself. Wait for the green check (a few minutes).
   If it does not start, open **Actions > Build pod image > Run workflow**.
4. Make the image public: on your GitHub profile open **Packages**, click `krea-lean-comfyui`, then
   **Package settings > Change visibility > Public**.
5. In RunPod open your template **Krea Lean ComfyUI** and edit it:
   - **Container image:** `ghcr.io/YOURNAME/krea-lean-comfyui:latest` (YOURNAME is your GitHub name in lowercase)
   - **Exposed HTTP ports:** add `3000` (keep 8188, 8080 and 8888)
   - keep the `CIVITAI_API_KEY` environment variable as it is
6. Deploy a pod from the template. When it starts, open the **Connect** tab and click the **port 3000** link. Watch the page, and click **Open ComfyUI** when it appears.

## Option B (one pasted line): no image needed

1. Do steps 1 and 2 above (you can skip steps 3 and 4).
2. Add `3000` to the template's exposed HTTP ports (step 5, only the ports line).
3. Deploy a pod from your normal template. Open its JupyterLab terminal and paste this one line
   (replace YOURNAME and the repository name if you chose a different one):

```
PODSETUP_RAW=https://raw.githubusercontent.com/YOURNAME/krea-pod/main/podsetup bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOURNAME/krea-pod/main/podsetup/boot.sh)"
```

4. Open the **port 3000** link from the Connect tab to watch it.

## Public or private

- **Public** is the easiest and everything above works as written. Anyone could read the scripts and see which models and LoRAs you use.
- **Private** repository: the build still works, but you must make the package public in step 4 for RunPod to pull it, and for
  Option B the pasted line needs an access token, which is more fiddly.

## Changing things later

Edit the lists at the top of `podsetup/setup.sh` (on GitHub, click the file and the pencil icon). For Option A, saving the
change rebuilds the image automatically; start new pods after the green check. Option B picks up the change straight away.

## If something goes wrong

- The progress page lists anything that did not install. A CivitAI file that fails with HTTP 401, 403 or 404 usually means the
  `CIVITAI_API_KEY` secret is missing from the template.
- The full log is in `/workspace/setup.log` and `/workspace/podsetup/boot.log` on the pod.
- If ComfyUI shows missing nodes after the page says it is ready, restart ComfyUI from the Manager and reload the page.
