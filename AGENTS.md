# AGENTS.md — MDM Móvil

INEGI fork of [MerginMaps/mobile](https://github.com/MerginMaps/mobile). C++17 + Qt6 QML, built with CMake + vcpkg.

---

## Build

The build system expects this sibling-directory layout:

```
mm1/
  build/      ← out-of-source build dir
  vcpkg/      ← vcpkg at commit pinned in VCPKG_BASELINE
  mobile/     ← this repo
```

**Bootstrap vcpkg first** (commit SHA is in `VCPKG_BASELINE`):
```bash
cd ../vcpkg && git checkout $(cat ../mobile/VCPKG_BASELINE) && ./bootstrap-vcpkg.sh
```

**Linux configure (canonical):**
```bash
cmake \
  -DCMAKE_BUILD_TYPE=Debug \
  -DVCPKG_TARGET_TRIPLET=x64-linux \
  -DCMAKE_TOOLCHAIN_FILE=../vcpkg/scripts/buildsystems/vcpkg.cmake \
  -DUSE_MM_SERVER_API_KEY=FALSE \
  -DENABLE_TESTS=TRUE \
  -GNinja \
  -S ../mobile
ninja
```

First build compiles Qt, GDAL, QGIS from source via vcpkg — takes ~1 hour without ccache. Use `-DCMAKE_CXX_COMPILER_LAUNCHER=ccache`.

**Platform triplets:** `x64-linux`, `arm64-android`, `arm64-ios`, `arm64-osx`, `x64-windows`.

**iOS must be Release/RelWithDebInfo** — Debug builds crash on Qt internal asserts.

**cmake 4.0.1 is broken for macOS** (empty `-isysroot`). CI pins `3.31.6`.

---

## Tests

```bash
cd build/
xvfb-run --server-args="-screen 0 640x480x24" ctest --output-on-failure   # Linux headless
ctest --output-on-failure                                                    # other platforms
```

Run a single test suite by passing its name directly to the binary:
```bash
./app/MerginMaps --testUtils
./app/MerginMaps --testFormEditors
```

Tests requiring network need env vars:
```
TEST_MERGIN_URL=https://app.dev.merginmaps.com/
TEST_API_USERNAME=test_mobileapp
TEST_API_PASSWORD=<secret>
```
Do **not** run `testMerginApi` in parallel — the test user is single-user.

`QT_QPA_PLATFORM=offscreen` is required on headless Linux.

---

## CI

All CI jobs have `if: github.repository == 'MerginMaps/mobile'` — they are **skipped** in this fork unless changed.

Qt version pinned in CI: **6.8.3**. CMake: **3.31.6**.

---

## Branding And Identity

This fork uses:
- `APPLICATION_NAME = "MDM móvil"`
- `ORGANIZATION_NAME = "INEGI"`
- `ORGANIZATION_DOMAIN = "mx.org.inegi"`

Runtime logs identify the app as `MDM Movil App`.

On Windows, `QStandardPaths::AppDataLocation` resolves under `.../Roaming/INEGI/Input`, so `QGIS_QUICK_DATA_PATH` becomes `.../INEGI/Input/INPUT`.

---

## Android Package Name

Android package / namespace is `inegi.org.mx`.

Key implications:
- Java sources live in `app/android/src/inegi/org/mx/`
- `FileProvider` authority is `inegi.org.mx.fileprovider`
- JNI class names must use `inegi/org/mx/...`
- Android tracking intent/action keys use `inegi.org.mx.tracking.*`

If Android integrations are renamed again, update manifest entries, Gradle namespace, Java package declarations, JNI strings, `FileProvider` authorities, and tracking action keys together.

---

## Directory Ownership

```
app/qml/             ← All QML UI
  main.qml           ← Root ApplicationWindow + state machine
  components/        ← MM-prefixed reusable primitives
  inputs/            ← Form input widgets
  tables/            ← INEGI-custom: SQLite table/DB management
  layers/            ← Layer management panels
  map/               ← Map canvas controller
  form/              ← Feature attribute forms
app/mmstyle.h        ← Design token singleton (exposed as __style)
app/dbmanager.cpp/h  ← INEGI-custom: SQLite DBManager (exposed as __dbManager)
app/android/src/inegi/org/mx/ ← Android package sources (`inegi.org.mx`)
core/                ← Project management + upstream Mergin code (UI/startup sync disabled in this fork)
test/                ← ctest registration + test_data fixtures
gallery/             ← Standalone UI component gallery app
scripts/             ← format_cpp.bash, format_cmake.bash, cppcheck.bash
```

---

## QML Architecture

### State machine (`main.qml`)

Three top-level states drive what is visible:

| State | Effect |
|---|---|
| `"map"` | Main map view |
| `"projects"` | Project listing |
| `"misc"` | Settings, GPS, layer management |

**INEGI customisation:** `Component.onCompleted` forces `stateManager.state = "map"` immediately (upstream default was `"projects"`).

### `mapPanelsStackView`

Full-screen `StackView` overlaid on the map. Panels are pushed as `Component` items.

**Correct close pattern** — always use `clear()`, matching how `MMLayersController` works:
```qml
// main.qml wiring:
onClose: {
  mapPanelsStackView.clear(StackView.PopTransition)
  stateManager.state = "map"
}
```
Using `.pop()` instead of `.clear()` may leave the panel visible when it is the only item.

**Reference pattern** — `MMLayersController` (`app/qml/layers/`):
- Root is `Item` (not `MMPage`) with `anchors.fill: parent`
- Has its own internal `StackView` for sub-navigation
- Emits `signal close()` → wired in `main.qml` to `mapPanelsStackView.clear()`

### `MMPage`

Full-screen page. Use for panels pushed into `mapPanelsStackView`.
- `property alias pageHeader` — title and back button (`pageHeader.title: "..."`)
- `property alias pageContent` — children go here
- `signal backClicked()` — also fires on hardware Back/Escape
- `onBackClicked:` is declared at the **MMPage root level**, not inside `pageHeader { }`
- `implicitHeight/Width` resolve from `ApplicationWindow.window` — it fills correctly when in a StackView

### `MMDrawer`

Bottom-sheet drawer.
- `property alias drawerHeader` — title + close button
- `property alias drawerContent` — children
- Use for modal/supplementary workflows, not full navigation

### `__style` design tokens

`mmstyle.h` registers `MMStyle` as QML context property `__style`. All values are constant. **Never hard-code colors, sizes, or asset paths** — always use `__style.*`.

Key token groups:
- **Fonts:** `__style.h1`–`__style.h3`, `__style.t1`–`__style.t5`, `__style.p1`–`__style.p7` (no `h4`)
- **Spacing:** `spacing2`, `spacing5`, `spacing10`, `spacing12`, `spacing20`, `spacing30`, `spacing40` — `spacing4`, `spacing8`, `spacing16` **do not exist**
- **Margins:** `margin1`–`margin54` (e.g. `margin16`, `margin20`)
- **Colors:** `grassColor`, `forestColor`, `nightColor`, `polarColor`, `lightGreenColor`, `negativeLightColor`, `grapeColor`, `negativeColor`, etc.
- **Rows:** `row40`, `row50`, `row60`, `row80`
- **Icons:** `__style.backIcon`, `__style.closeIcon`, `__style.addIcon`, `__style.arrowUpIcon`, etc. (100+)
- **Round button:** uses `iconSource:` property, not `source:`

### Qt6 QML quirks

- `TextInput` does **not** have `placeholderText` in Qt6. Use `TextField` with `background: Item {}` instead.
- `MMRoundButton` property is `iconSource:`, not `source:`.

---

## Code Style

**C++:** Auto-formatted with `astyle 3.4.13`. Run `scripts/format_cpp.bash` before committing — CI fails on violations.

**CMake:** Auto-formatted with `cmake-format`. Run `scripts/format_cmake.bash` before committing — CI fails on violations.

**QML:** 2-space indent. No automated checker. Follow [Furkanzmc QML Coding Guide](https://github.com/Furkanzmc/QML-Coding-Guide) with 2 spaces. Property order: required → properties → signals → position/size → other → attached → states → handlers → visual children → non-visual children → JS functions. No chained ternary operators.

---

## Secrets

`core/merginsecrets.cpp.enc` is the encrypted API key file. **Never commit the decrypted form.** Decrypt with:
```bash
openssl aes-256-cbc -d -in core/merginsecrets.cpp.enc -out core/merginsecrets.cpp -md md5
```
Password is in Lutra's password manager; CI uses `MERGINSECRETS_DECRYPT_KEY` secret. Set `-DUSE_MM_SERVER_API_KEY=FALSE` to skip this entirely in local dev.

---

## Mergin Status In This Fork

Cloud sync / Mergin-facing UI is intentionally disabled in this fork.

Current expectations:
- Do **not** re-enable startup calls to `/config` or `/ping` in `core/merginapi.cpp` unless explicitly requested
- Keep login, workspace, explore, and sync UI hidden unless explicitly requested
- Prefer local project import/open workflows over cloud flows
- Treat `core/` Mergin code as upstream legacy/infrastructure, not the active product surface

---

## INEGI-Specific Additions

- `app/qml/tables/` — full SQLite database/table management UI (not in upstream)
- `app/dbmanager.cpp/h` — `DBManager` C++ class, exposed to QML as `__dbManager`
- Toolbar entry `Tablas` opens the SQLite database manager flow from `main.qml`

---

## Recent INEGI Notes

- Imported local projects may not have a Mergin project ID; panel-close logic must not depend only on `activeProjectId`
- `MMProjectController.hidePanel()` should also allow the loaded-project case (`__activeProject.isProjectLoaded()`) for imported local projects
- SQLite table editing uses a manual-submit workflow: users can add multiple rows before pressing save
- `MMDatabaseManagerPage` should display column headers and consume `rowCount` as a reactive property, not a one-off method call
