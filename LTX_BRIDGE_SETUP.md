# CTNETWORK Local LTX Bridge

This bridge is the approval-gated control surface between CTNETWORK and the local RunPod production factory at `/workspace/ctnetwork-local`.

## What it exposes

- Start a real local production job
- Read real job status/progress
- Retry a recoverable failure
- Run render/Shorts/QC actions through the real factory controller
- Retrieve output paths
- Retrieve authenticated finished artifacts from `ready_for_approval`

It intentionally does **not** expose publishing. Publishing remains behind Thump's explicit approval gate.

## Production deployment

The commissioning install creates the trusted controller executable at:

```bash
/workspace/ctnetwork-local/bin/ctnetwork-production-control
```

The bridge application is persisted at:

```bash
/workspace/ctnetwork-local/bridge/app.py
```

A local production launch uses:

```bash
LTX_BRIDGE_TOKEN="$(cat /workspace/ctnetwork-local/secrets/bridge_token)" \
LTX_CONTROL_CMD=/workspace/ctnetwork-local/bin/ctnetwork-production-control \
LTX_BRIDGE_STATE_DIR=/workspace/ctnetwork-local/bridge-state \
LTX_CONTROL_TIMEOUT_SECONDS=7200 \
PYTHONPATH=/workspace/ctnetwork-local/bridge \
/workspace/ctnetwork-local/envs/core/bin/python -m uvicorn app:app \
  --host 127.0.0.1 --port 8080
```

If remote ChatGPT access is later enabled, place an authenticated HTTPS reverse proxy in front of the service. Do not expose port 8080 directly to the public Internet.

## Real controller contract

`LTX_CONTROL_CMD` must point to the real CTNETWORK production controller. The production bridge explicitly rejects `fake_controller.py` or any controller path containing `fake_controller`.

The real controller calls the local factory stack:

- Qwen3-TTS for approved/authorized narrator references
- LTX-2.5 / LTX-2.5 DFR for local video generation
- FFmpeg for assembly, audio normalization, Shorts, thumbnail extraction and encoding
- deterministic QC and checksums
- `READY_FOR_APPROVAL` package generation

The executable receives JSON over stdin and returns JSON on stdout. See `ltx_bridge/CONTROL_PROTOCOL.md`.

## Required environment values

- `LTX_BRIDGE_TOKEN`: persistent bearer token stored under `/workspace/ctnetwork-local/secrets/bridge_token`.
- `LTX_CONTROL_CMD`: `/workspace/ctnetwork-local/bin/ctnetwork-production-control`.
- `LTX_BRIDGE_STATE_DIR`: `/workspace/ctnetwork-local/bridge-state`.
- `LTX_CONTROL_TIMEOUT_SECONDS`: use a production-safe value such as `7200` for GPU jobs.

## API surfaces

- `/health`
- `/openapi.json`
- `POST /v1/production/start`
- `GET /v1/production/{job_id}`
- retry/render/shorts/qc endpoints
- `GET /v1/production/{job_id}/outputs`
- `GET /v1/production/{job_id}/artifact/{artifact_name}`

Artifact downloads are restricted to files explicitly returned by the real controller and located under `/workspace/ctnetwork-local/ready_for_approval`.

## Locked network behavior

1. No Higgsfield dependency is required by the local CTNETWORK production path.
2. All active show lanes may use the local factory while preserving each show's locked audience-facing formula, narrator identity, visual identity and Shorts cadence.
3. A recoverable error may be retried automatically and only the failed stage should rerun when practical.
4. A hard narrator/reference/formula failure blocks only that show lane; no narrator or visual-identity substitution is allowed.
5. The bridge never publishes.
6. Factory output must stop at `READY_FOR_APPROVAL` with `publish_allowed=false` and `requires_manual_approval=true`.
7. Normal daily production still requires Thump's manual production start command; commissioning tests are the only automatic exception.
