# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build from command line
xcodebuild -scheme PangLouWallpaper -destination 'platform=macOS' build

# Check for errors only
xcodebuild -scheme PangLouWallpaper -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning:"
```

There are no automated tests. Open `PangLouWallpaper.xcodeproj` in Xcode to run the app.

## Secrets Setup

`Secrets.plist` is gitignored and must be created locally before building. Copy from `Secrets.plist.example` and fill in:
- `OSSAccessKeyId` / `OSSAccessKeySecret` — Aliyun OSS credentials
- `MeilisearchHost` — e.g. `https://xxx.meilisearch.io`
- `MeilisearchApiKey`

Both `OSSUploader` and `MeilisearchService` call `fatalError()` at launch if this file is missing.

## Architecture

**Single ViewModel pattern**: `WallpaperViewModel` (an `ObservableObject`) owns all app state and is passed as `@ObservedObject` throughout the view hierarchy. There is no routing framework — tab switching is just `viewModel.currentTab`.

### Data flow

```
Meilisearch Cloud ──search/CRUD──► WallpaperViewModel.searchResults  ──► "电脑壁纸" tab
Meilisearch Cloud ──getAllDocuments──► WallpaperViewModel.allWallpapers ──► "已下载"/"轮播" tabs
Aliyun OSS ──PUT──► file storage (fullURL points here)
UserDefaults ──encode/decode──► WallpaperCollection[] (合集 feature, local only)
```

**`displayWallpapers`** is the computed property that feeds the grid. It switches on `currentTab`:
- `.pc` → returns `searchResults` (already filtered/paginated by Meilisearch server-side)
- `.downloaded` / `.slideshow` / `.collection` → returns `applyLocalFilters(to:)` on a subset of `allWallpapers`
- `.upload` → returns all `allWallpapers` for manage mode

**`paginatedImages`** slices `displayWallpapers` for non-PC tabs; for `.pc` it returns `displayWallpapers` directly (server already paged).

### Key files

| File | Responsibility |
|---|---|
| `Models/Models.swift` | `WallpaperItem`, `WallpaperCollection`, `AppTab`, `WallpaperFit`, `PendingUploadItem` |
| `ViewModels/WallpaperViewModel.swift` | All state, search, upload, download, slideshow timer, collection CRUD |
| `Services/MeilisearchService.swift` | Meilisearch REST API wrapper (search, add, update, delete, getAll) |
| `OSSUploader.swift` | HMAC-SHA1 signed PUT to Aliyun OSS |
| `Managers/WallpaperCacheManager.swift` | Local disk cache; SHA256 URL hash → filename mapping |
| `Managers/DesktopVideoManager.swift` | Sets video wallpaper via a borderless `NSWindow` at `.desktopWindow` level |
| `Views/ContentView.swift` | Root layout: nav bar + grid + bottom bar + modal overlays (ZStack) |
| `Views/AppSections.swift` | `TopNavigationBarView`, `WallpaperGridView`, `CollectionsGridView`, `BottomFloatingBarView`, upload views |
| `Views/UIComponents.swift` | `WallpaperCardView`, `WallpaperPreviewView`, `EditWallpaperPopupView`, `AddToCollectionView`, filter popovers |

### Modal overlay pattern

All popups (preview, edit, add-to-collection) are implemented as `ZStack` overlays in `ContentView.swift`, each gated by a nullable `@Published` property on the ViewModel (e.g. `previewItem != nil`, `editingWallpaper != nil`, `addToCollectionTargetItem != nil`). They use increasing `zIndex` values (97–100).

### Xcode project file sync

The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+). New `.swift` files added anywhere under `PangLouWallpaper/` are automatically included in the build target — no `project.pbxproj` edits needed.

### SourceKit cross-file errors

SourceKit frequently shows "Cannot find type X in scope" errors across files in editor mode. These are indexing artifacts and do **not** indicate real compilation errors. Always verify with `xcodebuild` before treating them as real issues.

## Meilisearch filter syntax

Filters are built as strings and joined with `" AND "`:
```swift
filters.append("category = \"动漫\"")
filters.append("isVideo = false")
```
Filterable attributes are: `category`, `resolution`, `color`, `isVideo`. Searchable: `title`, `description`, `tags`.

## WallpaperItem ID

IDs are SHA256 hashes of the raw file bytes, computed at upload time. This makes uploads idempotent — re-uploading the same file is detected and skipped.
