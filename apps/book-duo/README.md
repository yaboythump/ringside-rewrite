# Quilune

Quilune is CTInteractive's premium, fold-aware EPUB reader for iPhone Duo.

- **Two-page spread:** unfold iPhone Duo and the book opens like a real one, a page on each side of the fold, with the fold as the spine. If the fold runs across the screen instead, the next page sits below it. Any wide screen without a fold gets a spread too, and the Appearance sheet can switch to one page at a time.
- **Turning pages:** tap the right or left side, or swipe. Tap the middle for the contents, the appearance sheet and a progress slider. Links and footnotes inside the book work; touch and hold a word to look it up.
- **Appearance:** Paper, Sepia, Dusk and Night themes, the book's own font or Serif / Sans / Rounded, text size, line spacing, margins and justification. Changes reflow the open page straight away.
- **Personal shelves:** tap **NEW SHELF** to create a named collection, long-press a book cover to add/remove it from collections, and long-press a shelf chip to rename or remove it. Deleting a collection never deletes a book.
- **Reading rhythm:** reading streaks count calendar days with actual page turns (not just opening a book) and are stored on-device in Application Support.
- **Cinematic opening:** when an EPUB finishes layout, its actual book cover unfolds into the reading view; Reduce Motion disables this animation.
- **Focus mode:** use the **FOCUS** button on the reader progress controls to hide all controls, the compact Library chip, and the page footer while maximizing page height. Tap the center to reveal controls and exit focus, or return to your shelf.
- **Library:** search and filter titles, view reading progress, and tap **+** to add `.epub` files, share them to Quilune, or drop them into Files › On My iPhone › Book Duo. Each book remembers where you stopped, and the most recent one shows up as *Continue reading*.
- **Included book:** *Alice's Adventures in Wonderland* with Tenniel's illustrations, from [Standard Ebooks](https://standardebooks.org) (public domain, CC0). `sample/build_sample.py` rebuilds it from their source.

DRM-protected store books can't be opened.

## How it works

| Path | What it is |
|---|---|
| `ios/BookDuo/ZipReader.swift` | Reads the EPUB's ZIP container (Apple's Compression framework, no third-party code) |
| `ios/BookDuo/EPUB.swift` | Package, spine and table of contents (EPUB 3 nav or EPUB 2 NCX); unpacks each book once |
| `ios/BookDuo/Resources/reader.js` | Page engine: lays each chapter out in page-wide CSS columns and slides between them |
| `ios/BookDuo/PageWebView.swift` | One page: a WebKit view that runs the page engine |
| `ios/BookDuo/ReaderModel.swift` | Fold-aware page layout and the reading position |
| `ios/BookDuo/ReaderView.swift` | Reader screen, contents and appearance |
| `ios/BookDuo/LibraryView.swift`, `BookLibrary.swift` | Library, import and saved positions |

On iPhone Duo the fold comes from `GeometryProxy.reservedRegions(kind: .division)` (iOS 27.1), which is Apple's recommended way to lay out around it. Each side of the spread is its own page view showing the same chapter, one page apart.

## Getting it on TestFlight

1. Merge the pull request. GitHub's Mac builds the app.
2. One time only: in App Store Connect go to **Apps → + → New App**, name it **Book Duo** and pick bundle ID `com.ctnetworkstudios.bookduo`. (The upload step registers the bundle ID if it isn't listed yet; run it once and it will appear.)
3. Go to **Actions → Book Duo TestFlight → Run workflow** on `main`. The build appears in TestFlight a few minutes later.

The upload uses the same `ringside-testflight` signing secrets as the other apps.

## Branding

Quilune is the on-device display name and product brand. The Xcode target, internal source folder, and bundle ID `com.ctnetworkstudios.bookduo` remain unchanged so an update can replace the existing TestFlight installation without losing reading positions. The App Store Connect listing name is managed separately.
