# CTNETWORK LTX Controller Protocol

The bridge talks to one trusted executable on the LTX server, configured with `LTX_CONTROL_CMD`.

The executable is called as:

```bash
$LTX_CONTROL_CMD <action>
```

It receives one JSON object on stdin and MUST return one JSON object on stdout.

Supported actions:

- `start`
- `status`
- `retry`
- `render`
- `shorts`
- `qc`
- `outputs`

The bridge always injects `"publish": false`.

## Start payload

```json
{
  "job_id": "bridge-generated-id",
  "show": "Hip Hop What If",
  "episode": "What If Dipset Never Broke Up?",
  "auto_fix": true,
  "publish": false,
  "package_ref": "HipHopWhatIf_Dipset_Production_Package.txt",
  "visual_refs": ["Cinematic What-If Documentary Storyboards.png"],
  "narrator": {
    "provider": "Higgsfield",
    "model": "seed_audio",
    "voice_id": "05bd642c-3e9d-55a1-aa26-43fea30a3e94",
    "voice_type": "preset"
  },
  "shorts_count": 5,
  "metadata": {}
}
```

## Controller response

Minimum response:

```json
{"status":"running"}
```

Recommended final QC response:

```json
{
  "status": "ready_for_review",
  "qc_passed": true,
  "master": "/outputs/show/episode/final.mp4",
  "shorts": ["/outputs/show/episode/short_01.mp4"],
  "thumbnail": "/outputs/show/episode/thumbnail.png",
  "metadata": "/outputs/show/episode/metadata.json"
}
```

Recognized terminal statuses:

- `ready_for_review`, `ready`, `complete`, `completed`
- `blocked`
- `failed`, `error`

## Auto-fix rule

When the bridge calls `retry`, the controller should retry only recoverable failures such as transient generation errors, bad encode, missing derived output, audio normalization/QC failure, or a retryable provider/server error.

Hard locked failures MUST return `blocked`, for example:

- exact narrator runtime unavailable
- mandatory visual reference missing
- current episode package ambiguous/missing
- locked Shorts count/formula cannot be satisfied
- a required factual/source gate fails

Do not substitute another narrator, visual identity, show formula, or episode to clear a hard block.

## Publishing rule

The production controller must never publish when called through this bridge. The bridge does not expose a publishing action and always supplies `publish=false`.
