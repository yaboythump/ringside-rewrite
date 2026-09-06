#!/usr/bin/env bash
set -euo pipefail

API_URL="https://api.upload-post.com/api/upload"
AUTH_URL="https://api.upload-post.com/api/uploadposts/me"
PROFILE="${UPLOAD_POST_PROFILE:-YouTube}"
PAGE_ID="${RINGSIDE_FACEBOOK_PAGE_ID:-363068784190156}"
API_KEY="${UPLOAD_POST_API_KEY:-}"

if [[ -z "$API_KEY" ]]; then
  echo "::error::UPLOAD_POST_API_KEY is not configured."
  exit 1
fi

if [[ -z "$PAGE_ID" ]]; then
  echo "::error::RINGSIDE_FACEBOOK_PAGE_ID is not configured."
  exit 1
fi

echo "Validating Upload-Post API key before sending video bytes..."
if ! curl --silent --show-error --fail-with-body \
  -H "Authorization: Apikey $API_KEY" \
  "$AUTH_URL" >/dev/null; then
  echo "::error::UPLOAD_POST_API_KEY is invalid or expired. Replace the GitHub Actions secret before retrying."
  exit 1
fi
echo "Upload-Post API key validated."

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

  final_hash="$(sha256sum "$final" | cut -c1-16)"
  echo "Publishing full episode to Facebook: $title"
  curl --fail-with-body --retry 3 --retry-delay 2 \
    -X POST "$API_URL" \
    -H "Authorization: Apikey $API_KEY" \
    -H "Idempotency-Key: ringside-facebook-${slug}-full-${final_hash}" \
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
    short_hash="$(sha256sum "$short" | cut -c1-16)"

    upload_args=(
      --fail-with-body --retry 3 --retry-delay 2
      -X POST "$API_URL"
      -H "Authorization: Apikey $API_KEY"
      -H "Idempotency-Key: ringside-facebook-${slug}-short-${short_num}-${short_hash}"
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
