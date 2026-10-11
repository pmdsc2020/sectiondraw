# SectionDraw

Offline Flutter app for quick GPS cross-section surveys of nalas, streams and field sections.
Walk from the **left bank to the right bank**, capture a point every few metres, and get a
2D section (distance vs elevation) that you can export as **CSV** and **PNG**.

## Features

- Multiple sections, each with name, village/location and date — stored on the phone (works fully offline)
- Live **GPS accuracy** card (green ≤ 5 m, orange ≤ 10 m, red > 10 m), vertical accuracy, lat/long, GPS altitude
- **CAPTURE POINT** button with optional averaging (Off / 5 s / 10 s of readings per point)
- Optional note per point, with one-tap chips: Left bank, Bed, Water edge, Right bank
- "From last point" distance so you know when you have walked the next few metres
- **Reference elevation**: give point 1 a local value (e.g. 100.000 m); all other points = reference + GPS height difference from point 1. Can be set before or after capturing, or cleared to use raw GPS altitude
- Distance options: **Walked path** (cumulative distance from the first point) or **Straight line** (points projected onto the line first → last point, removes walking zig-zag)
- Graph with connected line, elevation value at every point, lowest point (bed) in blue, pinch-to-zoom
- Summary: width, lowest (bed), left/right bank, depth of bed below the lower bank, area below lower bank level
- Points list: edit note, delete point, undo last
- **Export CSV** (Excel-ready, with summary and all raw GPS data) and **Export PNG** (2000 × 1300 drawing with Distance / RL rows under the section, like a standard engineering cross-section). Export opens the share menu (Drive, Files, WhatsApp, Gmail); a copy is also kept inside the app.

## Get the APK without installing Flutter (GitHub builds it)

1. On GitHub create a new repository, e.g. `sectiondraw`.
2. Upload **all** files from this folder, including the `.github/workflows/build-apk.yml` file.
   - From a computer: unzip, then drag the folder contents into *Add file → Upload files*.
   - If the `.github` folder did not upload (it is a hidden folder on some systems), use
     *Add file → Create new file*, type the name `.github/workflows/build-apk.yml` and paste the file's contents.
3. Open the **Actions** tab. The "Build SectionDraw APK" job runs automatically (about 6–10 minutes).
4. When it is green, open **Releases → apk-latest → SectionDraw.apk** and download it on the phone.
   Allow "Install unknown apps" for the browser/Files app, then install.

Every new upload/commit rebuilds the APK at the same link, so you can share one link with field staff.

## Build on your own computer (if Flutter is installed)

```bash
bash tool/prepare_android.sh     # creates the android/ folder and adds GPS permissions
flutter pub get
flutter run                      # phone connected by USB, or
flutter build apk --release      # APK in build/app/outputs/flutter-apk/
```

On Windows without bash: run `flutter create --platforms=android --org in.dsc --project-name sectiondraw .`,
delete `test/widget_test.dart`, and add these two lines above `<application` in
`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

iPhone (needs a Mac): `flutter create --platforms=ios .` and add `NSLocationWhenInUseUsageDescription`
("SectionDraw uses GPS to record survey points") to `ios/Runner/Info.plist`.

## Field method and accuracy

- Phone GPS height is the weakest measurement: vertical error is usually 1.5–3× the horizontal accuracy shown.
  Wait for GOOD (green) accuracy, use 5 s or 10 s averaging, and hold the phone at the same height for every point.
- On Android the raw GPS altitude is height above the WGS84 ellipsoid, which in India differs from mean sea level
  by tens of metres. Only the **differences** between points matter for the section, so set a
  **reference elevation** for point 1 (a local datum such as 100.000 m, or a known RL / benchmark).
- "Walked path" adds any side-to-side wandering to the width; use "Straight line" when the walk was not straight.
- Results are for quick planning. Confirm design levels with an auto level or total station.
- Data is stored inside the app. Uninstalling the app deletes it — export CSV before uninstalling.

## Project layout

```
lib/main.dart            app + theme
lib/home_screen.dart     section list, new section, rename/delete, about
lib/section_screen.dart  CAPTURE / POINTS / GRAPH tabs, GPS handling
lib/section_painter.dart cross-section drawing (screen and PNG)
lib/export.dart          CSV + PNG export and sharing
lib/models.dart          data model, distance / elevation / area calculations
lib/storage.dart         offline JSON storage
test/models_test.dart    unit tests for the survey calculations
tool/prepare_android.sh  generates Android files + permissions
```

Packages: `geolocator` (GPS), `path_provider` (storage), `share_plus` (export sharing).

Developed by Jitendra Sonawane, Agriculture Engineer, 7720045808
