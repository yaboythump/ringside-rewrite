#!/usr/bin/env python3
import secrets
import time
import requests
import ringside_s2e01_server_assets as base

GPU_CANDIDATES = [
    "NVIDIA L40S",
    "NVIDIA L40",
    "NVIDIA RTX A6000",
    "NVIDIA A40",
    "NVIDIA RTX 6000 Ada Generation",
    "NVIDIA A100 80GB PCIe",
    "NVIDIA A100-SXM4-80GB",
    "NVIDIA H100 PCIe",
    "NVIDIA H100 80GB HBM3",
    "NVIDIA RTX PRO 6000 Blackwell Server Edition",
    "NVIDIA GeForce RTX 5090",
    "NVIDIA RTX PRO 4500 Blackwell",
]


def force_create_pod():
    password = secrets.token_hex(24)
    common = {
        "name": f"ringside-s2e01-rebuild-{int(time.time())}",
        "imageName": "runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404",
        "cloudType": "ALL",
        "computeType": "GPU",
        "gpuCount": 1,
        "dataCenterIds": [base.DC],
        "dataCenterPriority": "availability",
        "containerDiskInGb": 40,
        "networkVolumeId": base.VOLUME,
        "volumeMountPath": "/workspace",
        "ports": ["8888/http", "22/tcp"],
        "env": {"JUPYTER_PASSWORD": password},
    }

    attempts = []
    # First let RunPod choose among every compatible GPU we can use.
    attempts.append({**common, "gpuTypeIds": GPU_CANDIDATES, "gpuTypePriority": "availability"})
    # If the multi-GPU selector is rejected, try each type independently.
    attempts.extend({**common, "gpuTypeIds": [gpu]} for gpu in GPU_CANDIDATES)

    last = None
    for idx, payload in enumerate(attempts, 1):
        try:
            print("FRESH_POD_ATTEMPT", idx, payload["gpuTypeIds"], flush=True)
            r = requests.post(
                "https://rest.runpod.io/v1/pods",
                headers={**base.AUTH, "Content-Type": "application/json"},
                json=payload,
                timeout=60,
            )
            print("FRESH_POD_HTTP", r.status_code, r.text[:1200], flush=True)
            if not r.ok:
                last = RuntimeError(f"HTTP {r.status_code}: {r.text[:600]}")
                time.sleep(2)
                continue
            pod = r.json()
            pod_id = pod.get("id")
            if not pod_id:
                last = RuntimeError(f"missing pod id: {pod}")
                continue
            print("FRESH_POD_CREATED", pod_id, pod.get("gpu", pod.get("gpuTypeId")), flush=True)
            return pod_id, password
        except Exception as exc:
            last = exc
            print("FRESH_POD_ERROR", idx, repr(exc), flush=True)
            time.sleep(2)
    raise RuntimeError(f"No EU-RO-1 GPU could be allocated: {last!r}")


# Make the retry layer's fallback creator use this allocator.
base.create_pod = force_create_pod
# Importing the hardened retry module runs base.main() after installing its
# Kevin reference, one-load Qwen batch, ffmpeg bootstrap, login and websocket fixes.
import ringside_s2e01_server_assets_retry  # noqa: F401,E402
