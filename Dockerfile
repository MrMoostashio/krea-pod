# Custom pod image: RunPod's official ComfyUI image plus our automatic setup.
# Built for you by GitHub (see .github/workflows/build-image.yml); you never build it by hand.
FROM runpod/comfyui:1.7.0-comfyuiv0.35.0-cuda12.8

COPY podsetup/ /opt/podsetup/
RUN chmod +x /opt/podsetup/*.sh

ENTRYPOINT ["/opt/podsetup/entry.sh"]
