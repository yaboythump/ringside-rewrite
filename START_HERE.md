# Start Here

Next step: create a separate YouTube channel named **Ringside Rewrite**.

Do not rename AfterCall Cinema. This kit is designed to publish only when the connected YouTube channel title matches **RINGSIDE REWRITE**, which helps keep the wrestling channel separated from AfterCall.

## Channel setup

Use these brand assets:

- Profile picture: `assets/ringside-rewrite-avatar-youtube.png`
- Banner: `assets/ringside-rewrite-banner-youtube.png`

Suggested channel details:

- Name: **Ringside Rewrite**
- Handle to try: **@RingsideRewrite**
- Tagline: **Wrestling History. Booked Differently.**
- About text: `Unofficial wrestling what-if fantasy booking built from documented history. We start with the real timeline, then rewrite the booking.`

## First private test

Once the repo secrets are configured, run:

```bash
ringside dry-run --episode content/pilot/episode.json
ringside produce --episode content/pilot/episode.json
ringside publish --episode-dir output/sting-leads-the-invasion --privacy private
```

Review the private upload in YouTube Studio before approving anything public.

## When you are ready for scheduled uploads

Keep this off at first:

```bash
RINGSIDE_AUTO_PUBLISH=false
```

After 5-10 private episodes look right, set:

```bash
RINGSIDE_AUTO_PUBLISH=true
```

The local scheduler uses Tuesday, Thursday, and Saturday at noon Eastern. The included GitHub Actions workflow runs at `17:00 UTC` by default, which is noon EST and 1 PM EDT.
