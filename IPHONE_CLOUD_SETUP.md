# iPhone + Cloud Setup

This path lets GitHub run Ringside Rewrite in the cloud. Your iPhone is only used to create accounts, add encrypted secrets, start runs, and review private YouTube uploads.

## 1. Create the YouTube channel

Create a separate YouTube channel named **Ringside Rewrite**.

Use:

- Avatar: `assets/ringside-rewrite-avatar-youtube.png`
- Banner: `assets/ringside-rewrite-banner-youtube.png`
- Tagline: **Wrestling History. Booked Differently.**

## 2. Create the GitHub repo

1. Create a new private GitHub repository named `ringside-rewrite`.
2. Upload the contents of this kit's `ringside-rewrite` folder.
3. Keep the folder structure exactly as provided.

## 3. Add GitHub secrets

In GitHub, open **Settings → Secrets and variables → Actions → Secrets** and add:

- `OPENAI_API_KEY`
- `YOUTUBE_CLIENT_ID`
- `YOUTUBE_CLIENT_SECRET_VALUE`
- `YOUTUBE_REFRESH_TOKEN`

Optional extra safety variable:

- `YOUTUBE_EXPECTED_CHANNEL_ID`

The code already checks that the connected YouTube channel title is **RINGSIDE REWRITE**. The ID variable makes the lock stricter.

## 4. Run the free preflight

Open **Actions → RINGSIDE REWRITE free credential preflight → Run workflow**.

This verifies:

- OpenAI API key authentication
- Google refresh token authentication
- Correct YouTube channel connection

It does not generate content.

## 5. Run the pilot privately

Open **Actions → RINGSIDE REWRITE scheduled production → Run workflow** and choose:

- `pilot`

The workflow produces and uploads **What If Sting Led the WCW Invasion?** as a private video.

## 6. Review before public release

In YouTube Studio, check:

- Title and description
- Synthetic-media disclosure
- Sources and what-if disclaimer
- Thumbnail
- Captions
- Shorts cutdowns

Leave `RINGSIDE_AUTO_PUBLISH=false` until several private test episodes look right.

## 7. Turn on scheduled production

In **Settings → Secrets and variables → Actions → Variables**, set:

- `RINGSIDE_AUTO_PUBLISH=true`

The included GitHub Actions schedule runs Tuesday, Thursday, and Saturday at `17:00 UTC`, which is noon EST and 1 PM EDT. Change the cron time in `.github/workflows/produce.yml` if you want strict daylight-time noon.
