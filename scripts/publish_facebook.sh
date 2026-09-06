#!/usr/bin/env bash
set -euo pipefail

API_URL="https://api.upload-post.com/api/upload"
PROFILE="${UPLOAD_POST_PROFILE:-GTA}"
PAGE_ID="${RINGSIDE_FACEBOOK_PAGE_ID:-}"
API_KEY="${UPLOAD_POST_API_KEY:-}"
RUN_ID="${GITHUB_RUN_ID:-local}"

if [[ -z "$API_KEY" ]]; then
  echo "Facebook publish skipped: UPLOAD_POST_API_KEY is not configured."
  exit 0
fi

if [[ -z "$PAGE_ID" ]]; then
  echo "Facebook publish skipped: RINGSIDE_FACEBOOK_PAGE_ID is not configured."
  exit 0
fi

mapfile -t finals < <(find output -type f -name final.mp4 | sort)
if [[ ${#finals[@]} -eq 0 ]]; then
  echo "Facebook publish skipped: no finished final.mp4 files found."
  exit 0
fi

for final in "${finals[@]}"; do
  episode_dir="$(dirname "$final")"
  episode_json="$episode_dir/episode.json"
  slug="$(basename "$episode_dir")"

  if [[ -f "$episode_json" ]]; then
    title="$(jq -r '.episode_title // .title // "Ringside Rewrite"' "$episode_json")"
    description="$(jq -r '.description // ""' "$episode_json")"
    hashtags="$(jq -r '(.hashtags // []) | join(" ")' "$episode_json")"
  else
    title="Ringside Rewrite"
    description=""
    hashtags="#RingsideRewrite #WrestlingWhatIf #FantasyBooking"
  fi

  facebook_description="$description"
  if [[ -n "$hashtags" ]]; then
    facebook_description="${facebook_description}${facebook_description:+$'\n\n'}${hashtags}"
  fi

  echo "Publishing full episode to Facebook: $title"
  curl --fail-with-body --retry 3 --retry-all-errors \
    -X POST "$API_URL" \
    -H "Authorization: Apikey $API_KEY" \
    -H "Idempotency-Key: ringside-facebook-${RUN_ID}-${slug}-full" \
    -F "user=$PROFILE" \
    -F "platform[]=facebook" \
    -F "facebook_page_id=$PAGE_ID" \
    -F "facebook_media_type=VIDEO" \
    -F "facebook_title=$title" \
    -F "facebook_description=$facebook_description" \
    -F "video=@$final;type=video/mp4" \
    -F "async_upload=true"

  mapfile -t shorts < <(find "$episode_dir/shorts" -maxdepth 1 -type f -name '*.mp4' 2>/dev/null | sort)
  short_num=0
  for short in "${shorts[@]}"; do
    short_num=$((short_num + 1))
    short_title="$title | Short $short_num"

    upload_args=(
      --fail-with-body --retry 3 --retry-all-errors
      -X POST "$API_URL"
      -H "Authorization: Apikey $API_KEY"
      -H "Idempotency-Key: ringside-facebook-${RUN_ID}-${slug}-short-${short_num}"
      -F "user=$PROFILE"
      -F "platform[]=facebook"
      -F "facebook_page_id=$PAGE_ID"
      -F "facebook_media_type=REELS"
      -F "facebook_title=$short_title"
      -F "facebook_description=$facebook_description"
      -F "video=@$short;type=video/mp4"
      -F "async_upload=true"
    )

    if (( short_num > 1 )); then
      scheduled_date="$(date -u -d "+$((short_num - 1)) hour" +'%Y-%m-%dT%H:%M:%SZ')"
      upload_args+=( -F "scheduled_date=$scheduled_date" )
      echo "Scheduling Facebook Reel $short_num for $scheduled_date"
    else
      echo "Publishing Facebook Reel $short_num now"
    fi

    curl "${upload_args[@]}"
  done
done
