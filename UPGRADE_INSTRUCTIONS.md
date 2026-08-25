# Ringside Rewrite Lean Premium Upgrade v2

This upgrade keeps the Episode 1 illustration style while reducing production cost.

## Included

- Two full episodes per week: Tuesday and Saturday.
- 800-1,100 words and 14-16 premium images per new episode.
- Exactly three 30-55 second Shorts per episode.
- Short titles formatted as: `[Episode Name] — [Short Hook] #Shorts`.
- Parent episode name and full-video link in every Short description.
- Expanded, subject-specific tags for every Short.
- Character identity locks for gender presentation, skin tone, build, hair, era, and gear silhouette.
- Episode 1 remains grandfathered under its original 24-image settings.

## Phone installation

1. Upload the ZIP to the root of the `ringside-rewrite` GitHub repository.
2. Commit the upload.
3. Open **Actions**.
4. Open **Unzip Ringside Rewrite Kit**.
5. Tap **Run workflow** and select `main`.
6. Wait for a green check.

The ZIP intentionally does not overwrite `.github/workflows/produce.yml`, avoiding GitHub's workflow-permission rejection. After the main upgrade succeeds, replace that workflow separately with `workflow-update/produce.yml` to save finished MP4 files as downloadable artifacts for 14 days.

