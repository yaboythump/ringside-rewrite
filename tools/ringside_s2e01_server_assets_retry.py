#!/usr/bin/env python3
import time
import requests
import ringside_s2e01_server_assets as base

PREFERRED_POD_ID = "ugt1pe6ndmichc"


def resolve_or_create_pod():
    try:
        r = requests.get(f"https://rest.runpod.io/v1/pods/{PREFERRED_POD_ID}", headers=base.AUTH, timeout=30)
        if r.ok:
            pod = r.json()
            volume = pod.get("networkVolumeId") or (pod.get("networkVolume") or {}).get("id")
            password = (pod.get("env") or {}).get("JUPYTER_PASSWORD")
            if volume == base.VOLUME and password:
                state = pod.get("desiredStatus", "")
                print("PREFERRED_POD", PREFERRED_POD_ID, state, flush=True)
                if state != "RUNNING":
                    sr = requests.post(f"https://rest.runpod.io/v1/pods/{PREFERRED_POD_ID}/start", headers=base.AUTH, timeout=30)
                    sr.raise_for_status()
                return PREFERRED_POD_ID, password
    except Exception as exc:
        print("PREFERRED_POD_FALLBACK", repr(exc), flush=True)

    last = None
    for attempt in range(1, 7):
        try:
            print(f"CREATE_POD_ATTEMPT {attempt}/6", flush=True)
            return base.create_pod()
        except Exception as exc:
            last = exc
            print("CREATE_POD_RETRY", repr(exc), flush=True)
            time.sleep(min(30, attempt * 5))
    raise RuntimeError(f"Unable to resolve or create production pod: {last!r}")


base.create_pod = resolve_or_create_pod
base.main()
