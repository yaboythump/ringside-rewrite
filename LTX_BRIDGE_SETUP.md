# CTNETWORK LTX Bridge

This bridge gives ChatGPT a safe control surface for the existing CTNETWORK LTX production server.

## What it exposes

- Start a production job
- Read job status
- Retry a recoverable failure
- Render a master
- Build the locked Shorts package
- Run QC
- Retrieve output paths

It intentionally does **not** expose publishing. Publishing remains behind Thump's approval gate.

## Server deployment

Run this on the LTX server (or on a host that can call the existing LTX production controller):

```bash
docker build -f ltx_bridge/Dockerfile -t ctnetwork-ltx-bridge .
docker run -d \
  --name ctnetwork-ltx-bridge \
  --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -e LTX_BRIDGE_TOKEN='REPLACE_WITH_LONG_RANDOM_TOKEN' \
  -e LTX_CONTROL_CMD='/opt/ctnetwork/bin/production-control' \
  -e LTX_BRIDGE_STATE_DIR='/data/state' \
  -v /var/lib/ctnetwork-ltx-bridge:/data/state \
  ctnetwork-ltx-bridge
```

Place the HTTPS reverse proxy already used by the server in front of port 8080. Do not expose the container directly to the public Internet without TLS.

## Existing LTX controller contract

`LTX_CONTROL_CMD` must be a trusted executable. The bridge calls it with one action argument and sends JSON over stdin. See `ltx_bridge/CONTROL_PROTOCOL.md`.

Example:

```bash
/opt/ctnetwork/bin/production-control start < payload.json
```

The executable returns JSON on stdout.

## Required environment values

- `LTX_BRIDGE_TOKEN`: bearer token used by the ChatGPT integration.
- `LTX_CONTROL_CMD`: path to the existing LTX production controller executable.
- `LTX_BRIDGE_STATE_DIR`: persistent job-state folder.
- `LTX_CONTROL_TIMEOUT_SECONDS`: optional; defaults to 900.

## ChatGPT connection

The service automatically exposes OpenAPI at:

- `/openapi.json`

Connect the deployed HTTPS endpoint as the CTNETWORK LTX custom integration and configure bearer authentication with the same `LTX_BRIDGE_TOKEN`.

Once connected, ChatGPT can map commands such as:

- `START TODAY'S PRODUCTION`
- `check production status`
- `fix failed production automatically`
- `run QC`
- `show me finished outputs`

to the bridge endpoints.

## Locked network behavior

1. Johnny Facts is excluded from LTX and remains on its separate locked Higgsfield production method.
2. A recoverable error may be retried automatically.
3. A hard formula/narrator/reference failure blocks only that show lane.
4. No narrator substitution is permitted.
5. No visual identity substitution is permitted.
6. No change to a show's locked Shorts count is permitted.
7. The bridge never publishes.
8. Final status before approval is `READY FOR REVIEW`.
