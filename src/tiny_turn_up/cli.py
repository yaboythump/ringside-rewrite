from __future__ import annotations

import argparse
import sys

from .episode import list_episodes, load_episode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="tinyturnup", description="Tiny Turn Up video factory")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="show episodes and what each still needs")
    p = sub.add_parser("images", help="generate missing scene images + thumbnail (OpenAI)")
    p.add_argument("slug")
    p.add_argument("--force", action="store_true", help="regenerate even if files exist")
    p = sub.add_parser("make", help="images (if missing) + long video + Shorts + thumbnail")
    p.add_argument("slug")
    p.add_argument("--no-images", action="store_true", help="only use images/clips you supplied")
    sub.add_parser("auth", help="log in to the Tiny Turn Up YouTube channel (one time)")
    p = sub.add_parser("upload", help="upload long video + Shorts as Made for Kids")
    p.add_argument("slug")
    p.add_argument("--public", action="store_true", help="publish now (default: private for review)")
    p.add_argument("--publish-at", help="schedule, e.g. 2026-11-10T13:00:00Z")
    args = parser.parse_args(argv)

    try:
        if args.cmd == "list":
            for slug in list_episodes():
                ep = load_episode(slug)
                if ep.compile_from:
                    needs = "compilation"
                else:
                    have = sum(ep.scene_media(i).exists() for i in range(1, len(ep.scenes) + 1))
                    needs = ("song ✓" if ep.song.exists() else "NEEDS song.mp3") + f", scenes {have}/{len(ep.scenes)}"
                done = "rendered" if (ep.build / "long.mp4").exists() else "not rendered"
                up = "uploaded" if (ep.folder / "uploaded.json").exists() else ""
                print(f"{slug:28} {needs:32} {done:13} {up}")
        elif args.cmd == "images":
            from .produce import generate_images
            generate_images(load_episode(args.slug), force=args.force)
        elif args.cmd == "make":
            from .produce import produce
            produce(args.slug, images=not args.no_images)
        elif args.cmd == "auth":
            from .publish import youtube_service
            youtube_service(interactive=True)
            print("Tiny Turn Up channel connected.")
        elif args.cmd == "upload":
            from .publish import upload_episode
            upload_episode(load_episode(args.slug),
                           privacy="public" if args.public else "private",
                           publish_at=args.publish_at)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
