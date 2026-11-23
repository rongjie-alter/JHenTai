# Reader v2

Reader v2 is a rewrite of the gallery reading page, created to maintain a personal fork with a **better trackpad gesture reading experience** (smooth two-finger scroll, wobble-free pinch-to-zoom, Ctrl+wheel zoom) on desktop, while still working with touch on mobile.

- Code: `lib/src/pages/read_v2/`
- Settings: `lib/src/setting/read_v2_setting.dart` (`readV2Setting`)
- Route: `Routes.readV2` (`/read_v2`) → `ReadV2Page`, full-screen
- Every call site that opens a gallery (details page, online/archive/local downloads, download search) navigates to `Routes.readV2`. The v1 route (`Routes.read`, `lib/src/pages/read/`) is still registered but nothing navigates to it anymore.

> Last reviewed against branch `book_v2` at commit `1edc659` (2026-11-23).

## Design goals

1. **Trackpad first.** Treat `PointerPanZoom*` events (trackpad pinch / two-finger pan) as a first-class input and make zoom stable (no wobble, no accidental scrolling while pinching, cursor-anchored zoom).
2. **One reader, several reading modes.** Vertical continuous, horizontal continuous (LTR/RTL), single page, double page (LTR/RTL), switchable at runtime without losing position.
3. **Independent of v1.** Own page/logic/state, own image sources, own setting. Cross-cutting preferences (immersive mode, keep-screen-awake) are still read from the shared `readSetting`.

## Architecture

```
ReadV2Page (UI shell, menus, tap regions, keyboard)
 └─ ReadV2Logic (GetxController)  ── ReadV2State
     ├─ SlicingEngine ........... image indices → List<PageGroup>
     ├─ ReaderImageSource ....... where images/thumbnails come from
     └─ ReadingStrategy (one mounted at a time, chosen by mode)
         ├─ SinglePageStrategy ............ PageView + ReaderViewport
         ├─ DoublePageStrategy ............ PageView + ReaderViewport (wraps the spread)
         ├─ VerticalContinuousStrategy .... ZoomableScrollView + ScrollablePositionedList
         └─ HorizontalContinuousStrategy .. ZoomableScrollView + ScrollablePositionedList
```

Files:

| Path | Role |
|---|---|
| `read_v2_page.dart` | Widget tree: image layer, tap-region layer, top app bar (reading-mode menu, “first page alone” toggle), bottom menu (thumbnail strip + slider), bottom-right page/time info, keyboard + mouse-button shortcuts |
| `read_v2_logic.dart` | Lifecycle, mode switching, group ↔ image-index bookkeeping, progress persistence, tap/keyboard → advance/retreat |
| `read_v2_state.dart` | Holds `ReadPageInfo` (from `Get.arguments`), current mode/group/source, menu state, thumbnail-strip controllers |
| `slicing/` | `ReadingModeV2` enum, `PageGroup`, `SlicingEngine` |
| `strategy/` | `ReadingStrategyContext`/`ReadingStrategyState` contract, dispatcher, four concrete strategies |
| `viewport/` | `ReaderViewport` (page modes), `ZoomableScrollView` + `ZoomGuardScrollPhysics` (continuous modes) — **the trackpad logic lives here** |
| `data/` | `ReaderImageSource` interface and online / downloaded / archive implementations |
| `widget/` | `ReaderImage`, `ReaderThumbnail`, `StableSizeImageItem` |

### Entry data

The page is opened with a `ReadPageInfo` as `Get.arguments` (same model v1 uses). `ReadMode` selects the image source:

| `ReadMode` | Source |
|---|---|
| `online` | `OnlineImageSource(galleryUrl, pageCount)` |
| `downloaded` | `DownloadedImageSource.fromService(gid)` |
| `archive`, `local` | `ArchiveImageSource(images)` |

## Reading modes and slicing

`ReadingModeV2` has six values: `verticalContinuous`, `horizontalContinuousLTR`, `horizontalContinuousRTL`, `singlePage`, `doublePageLTR`, `doublePageRTL`. Helpers: `isContinuous`, `isPageBased`, `isDouble`, `isRightToLeft`, `isHorizontal`.

`SlicingEngine.slice()` turns `pageCount` into a list of `PageGroup`s:

- Non-double modes: one group per image.
- Double modes: pairs `(0,1), (2,3), …`. With `displayFirstPageAlone` the first image is its own group and pairing starts at index 1. A trailing odd image becomes a single group.
- Indices inside a group are always chronological. Direction is **not** applied by the engine: the strategy lays out RTL (e.g. `DoublePageStrategy._SpreadRow` puts the earlier page on the right).

`state.currentGroup` is the source of truth for position; `state.currentImageIndex` is `groups[currentGroup].first` and is what progress tracking, the page counter, the slider and the thumbnail highlight use.

### Switching mode / first-page-alone at runtime

`ReadV2Logic` listens (via `ever`) to `readV2Setting.readingMode` and `displayFirstPageAlone`. On change it re-slices with `_rebuildGroupsPreservingPosition()` (re-finds the group containing the last image index), replaces `state.strategyKey` with a fresh `GlobalKey` so the old strategy is torn down and the new one mounts at the right group, and refreshes the layout/menus.

## Strategies

All strategies implement `ReadingStrategyState`: `advance()`, `retreat()`, `jumpToGroup(int)`. The page logic keeps one `GlobalKey<ReadingStrategyState>` (`state.strategyKey`) and dispatches to whichever is mounted. They receive a read-only `ReadingStrategyContext` (mode, groups, initial group, source, `imageBuilder`, `onGroupChanged`, min/max scale, image spacing, page-turn-animation flag) and report position back through `onGroupChanged`.

| Strategy | Scrolling | Zoom | `advance` / `retreat` |
|---|---|---|---|
| Single page | `PageView` with `ZoomGuardScrollPhysics` | `ReaderViewport` per page, reset when the page changes (`resetKey`) | next/previous page (animated if `enablePageTurnAnime`, else jump) |
| Double page | `PageView` (`reverse` for RTL), `ZoomGuardScrollPhysics` | `ReaderViewport` wraps the whole spread | same as single |
| Vertical continuous | `ScrollablePositionedList` | `ZoomableScrollView` around the list | scroll by 0.9 × screen height (200 ms) |
| Horizontal continuous | `ScrollablePositionedList` (`reverse` for RTL) | `ZoomableScrollView` | scroll by 0.9 × screen width (200 ms) |

Notes:

- In continuous modes the “current group” is the lowest-index item that is at least partly visible (`itemTrailingEdge > 0 && itemLeadingEdge < 1`).
- In continuous RTL the list uses `reverse: true`, so a positive scroll offset already moves toward higher indices; the physical left/right → advance/retreat mapping is done in `ReadV2Logic.tapLeftRegion/tapRightRegion`, not in the strategy.
- Page strategies notify the logic from both `PageView.onPageChanged` and a `PageController` listener (rounded page). `ReadV2Logic.onStrategyGroupChanged` dedupes on `currentGroup`.
- Continuous items are wrapped in `StableSizeImageItem` so item extents don't change as images load (see below). Zoom state persists across items in continuous modes; in page modes it resets on page change.

## Trackpad & zoom handling (the reason v2 exists)

This is the most delicate part of the code and the product of several fixes (commits `604e96a`, `5ecd0f5`, `3d4a725`, `7795482`, `499b30c`, `56fe5e6`, `6659f20`). Two widgets implement it with nearly identical logic: `ReaderViewport` (page modes) and `ZoomableScrollView` (continuous modes, additionally handles Ctrl+wheel and reports scale changes).

### Building blocks

- **`InteractiveViewer`** provides touch pinch/pan and the matrix container, but its own handling of trackpad events is bypassed (see below).
- **Outer `Listener`** receives `onPointerPanZoomStart/Update/End` (trackpad pinch/pan) and, in `ZoomableScrollView`, `onPointerSignal` (wheel).
- **`ZoomGuardScrollPhysics`** is used as the physics of every inner `PageView` / `ScrollablePositionedList`.

### Problems solved and how

| Problem | Solution |
|---|---|
| A plain `InteractiveViewer` around a list swallows the drag arena, so the list can't scroll | `panEnabled` is bound to “zoomed” (`scale > 1.01`). At scale 1 the inner scrollable owns all drag/wheel/trackpad scroll natively |
| Wobble during trackpad pinch: `InteractiveViewer`'s scale/pan paths fight our own matrix writes | During a trackpad pinch (`_trackpadPinching`) set `panEnabled: false` and `scaleEnabled: false`, and drive the `TransformationController` ourselves from the `Listener`. Touch pinch still uses IV's `scaleEnabled` because pan-zoom events only come from trackpads |
| Image drifts when the finger centroid moves slightly during a pinch (Windows precision touchpads) | Focal point is captured at `PointerPanZoomStart` and reused for every update |
| Accumulated drift from per-event scaling | Idempotent, target-based scaling: target = `clamp(baseScale × event.scale, minScale, maxScale)`; the matrix is scaled by `target / current` about the locked focal point. `event.scale` is cumulative from gesture start, so `baseScale` is captured at start |
| The inner list/page view scrolls a few pixels (and flings) during a pinch because it also sees the pan part of the pan-zoom event | `ZoomGuardScrollPhysics` has a static `_pinching` flag. `ReaderViewport`/`ZoomableScrollView` call `beginPinch()` once `|scale − 1| > 0.001`; while set, `applyPhysicsToUserOffset` returns 0 and `createBallisticSimulation` returns null |
| Residual fling at gesture end | `endPinch()` is deferred with `Future.microtask` on `PointerPanZoomEnd`, so the scrollable's synchronous drag-end still sees the pinch and is suppressed |
| Pure two-finger pan in continuous mode must scroll, not zoom | `ZoomableScrollView` ignores updates with `|scale − 1| < 0.005` (kept looser than the 0.001 pinch-detect threshold to avoid jittery scaling) |
| Ctrl+wheel zoom vs. plain wheel scroll | `ZoomableScrollView` registers Ctrl+wheel with `PointerSignalResolver`; `ZoomGuardScrollPhysics.shouldAcceptUserOffset` returns false while Ctrl is held so the inner scrollable doesn't register first. Each notch steps the scale by 0.15, anchored at the cursor. Plain wheel is untouched. (Only in `ZoomableScrollView`; `ReaderViewport` does not currently handle Ctrl+wheel.) |
| Zooming out exposes empty space / image shifts on zoom-out | `_clampTranslation` after every direct matrix write. The bound is **asymmetric**, `tx ∈ [−(s−1)·w, 0]`, `ty ∈ [−(s−1)·h, 0]`, because the child origin is top-left. Cursor-anchored zoom naturally lands inside this range, so the cursor stays put; clamping only intervenes when the user drifts. A symmetric bound mis-clamped right/bottom-half focal points |
| Static pinch flag left set if the reader closes mid-pinch | `dispose()` calls `endPinch()` if `_trackpadPinching`; `_onPointerPanZoomEnd` schedules `endPinch` before `setState` since the event may arrive after dispose |

The static `_pinching` flag is acceptable because only one reader is mounted at a time.

### Gesture layering in the page

`ReadV2Page` stacks the image layer and a tap-region layer in `EHReadPageStack` (a `Stack` whose `hitTestChildren` hit-tests *all* children rather than stopping at the first). Both layers therefore receive pointer events and the gesture arena arbitrates:

- Page modes: three equal tap zones, left / centre / right → `tapLeftRegion` / `tapCenterRegion` / `tapRightRegion`. For RTL modes left means advance.
- Continuous modes: only a centre zone (middle 50 % of the width) that toggles the menu; scrolling and pinching are left to the layer underneath.

### Known limitations / things to watch

- `ZoomableScrollView`'s docs say the inner list is frozen while zoomed and that dragging pans the zoomed content; behaviour at high zoom near the list ends (and swiping `PageView` pages while zoomed) hasn't been documented or covered by tests — verify manually when changing this code.
- `ReaderViewport` has no Ctrl+wheel handler; `ZoomableScrollView` has no `resetKey`.
- The pinch/pan logic is duplicated across `reader_viewport.dart` and `zoomable_scroll_view.dart` (including `_clampTranslation`). Fix both when changing one.
- There are no automated tests; gesture changes are verified by hand on a real trackpad (Windows precision touchpad in particular).

## Image sources

`ReaderImageSource` (`data/reader_image_source.dart`) abstracts image/thumbnail access:

- Sync, cheap: `peekImage`, `peekImageMetadata`, `peekThumbnail`, `errorFor`, `isLocal`, `pageCount`.
- Async: `getImage`, `getThumbnail`, `reloadImage`.
- Streams: `imageReadyStream`, `thumbnailReadyStream` (emit the index that just became available; widgets rebuild only that item).
- `peekImage` = ready to render; `peekImageMetadata` = size info available even if the file isn't ready yet (e.g. still downloading).

### `OnlineImageSource`

Mirrors v1's pipeline but independent of it: thumbnail batch (detail page → thumbnails + image-page hrefs) → image page parse → `GalleryImage`. Requests go through an `EHExecutor` (concurrency 100, 10 requests/second), with 3 retries on `DioException`. Thumbnail batches populate every index in the batch and complete their waiters. If a batch fails to populate the requested index (e.g. thumbnails-per-page changed), the cached detail page is removed and it is re-requested. Errors are stored per index and surfaced to `ReaderImage`. `reloadImage` clears the disk cache for the URL, drops state and re-parses with the old `reloadKey`.

### `DownloadedImageSource` / `ArchiveImageSource`

Share `LocalImageSourceBase` (paths already known, no parsing). The downloaded source is backed by `galleryDownloadInfos[gid].images` and subscribes to the download service's per-image listener ids, so pages that finish downloading while the reader is open appear without reload; an image is only renderable when `downloadStatus == downloaded` (the service assigns `path` before the file is written). `getImage` for a not-yet-ready image returns a waiter completed by `notifyImageReady`. The archive source is a fixed list. Local sources return no `GalleryThumbnail`; the thumbnail widget renders the file itself.

## Widgets

- **`ReaderImage`** — requests the image on mount, listens to `imageReadyStream`, shows spinner / error with retry. Local images use `Image.file` (relative path resolved via `DownloadedImageSource.absolutePath` for downloads); online images use `ExtendedImage.network` with disk cache and memory cache cleared on dispose.
- **`StableSizeImageItem`** — locks the main-axis extent of a continuous-mode item from the known aspect ratio (image metadata → thumbnail size → half of the viewport as placeholder), so the list doesn't jump while images load (see commit `6659f20`, “Fix continuous unexpected jumping”). Rebuilds when the image or thumbnail for that index becomes ready.
- **`ReaderThumbnail`** — thumbnail strip cell; lazy batch request for online, small `Image.file` (`cacheWidth: 200`) for local.

## Page shell (`ReadV2Page`)

- Top menu: back button, title, “first page alone” toggle (double modes only) and a popup to pick the reading mode (labels are currently hard-coded English, not i18n).
- Bottom menu: optional thumbnail strip (`ScrollablePositionedList`, reversed in RTL) + slider (rotated 180° in RTL). Dragging calls `handleSlide` (updates counter live) and `handleSlideEnd` (jumps).
- Bottom-right status: `current/total` and clock, hidden while the menu is open, controlled by `showStatusInfo`.
- Desktop window chrome is added via `WindowWidgetMixin` when immersive mode is off.

### Keyboard / mouse

| Input | Action |
|---|---|
| Left / `A` | `onLeftPressed` (retreat; advance in RTL) |
| Right / `D` | `onRightPressed` (advance; retreat in RTL) |
| Up / PageUp | retreat (semantic previous) |
| Down / PageDown | advance (semantic next) |
| Space | toggle menu |
| `M` | toggle “first page alone” |
| F11 | toggle fullscreen |
| Esc / End / mouse button 5 | back |

## Settings (`ReadV2Setting`)

Persisted as JSON in the `local_config` table under `ConfigEnum.readV2Setting`, registered in the bean list in `main.dart`.

| Key | Default | Notes |
|---|---|---|
| `readingMode` | vertical continuous on mobile, horizontal continuous LTR on desktop | |
| `displayFirstPageAlone` | `true` | double-page modes |
| `imageSpace` | `6` | px between images / in a spread |
| `showThumbnails` | `true` | bottom strip |
| `showStatusInfo` | `true` | bottom-right info |
| `enablePageTurnAnime` | `true` | page modes |
| `minScale` / `maxScale` | `1.0` / `5.0` | zoom clamp |
| `preloadDistance`, `preloadDistanceLocal`, `enableBottomMenu` | `1`, `3` (iOS) / `8`, `false` | persisted but **not read by the v2 reader yet** |

Shared from `readSetting`: `enableImmersiveMode`, `keepScreenAwakeWhenReading`.

## Lifecycle & progress

- `onInit`: reads mode/first-page setting, builds source, slices groups, locates the group of `readPageInfo.initialIndex`.
- `onReady`: applies immersive mode, enables wakelock if configured, installs the listeners above, starts a 5-second timer that flushes progress.
- `onClose`: disposes listeners, focus node and source, disables wakelock, restores system UI on mobile, and flushes progress one last time.
- Progress is saved with `readProgressService.updateReadProgress(readProgressRecordStorageKey, currentImageIndex)`. `currentImageIndex` is the **first** image of the current group.

## Working on this fork

- Entry points to test: online gallery (details page), downloaded gallery, archive, local gallery.
- Manual trackpad checklist for gesture changes, in each of the four strategies: pinch in/out (no wobble, no scroll, cursor-anchored); pinch with drifting fingers; two-finger scroll at scale 1; pan while zoomed; Ctrl+wheel (continuous); zoom out fully (no empty margins); close the reader mid-pinch and reopen (no stuck frozen scrolling).
- Run `flutter analyze` before committing; there is no test suite for the reader.
