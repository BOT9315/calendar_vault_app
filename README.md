# 📅 Calendar Hidex App — Private Vault & Encrypted Gallery

A disguised, fully functional Calendar App hiding a secure, military-grade encrypted Photo, Video, and Document Vault. Built with **Flutter (Android)**, featuring **AES-256 encryption**, **Biometric Quick Unlock**, **Multi-Engine Private Browser** (Chrome, Firefox, UC Browser), and **Persistent Storage Architecture** ensuring your private files survive app uninstall and reinstallation.

---

## 📥 Download the App

**[⬇️ Download Calendar Hidex APK (v1.0)](https://github.com/BOT9315/calendar_vault_app/releases/latest/download/Calendar_Hidex_App_v1.0.apk)**

1. On your Android phone, tap the download link above. The APK will download.
2. Once it's downloaded, open the file. If Android asks for "Install unknown apps" permission, allow it for your browser (Chrome or Firefox).
3. Tap Install, then open the app.

> This is a direct link from GitHub Releases, so the APK starts downloading as soon as you tap it.

---

## 🌟 Key Features

### 1. 📅 Elegant Decoy Calendar Disguise
- Fully functional daily calendar, month switcher, light/dark themes, and real decoy daily planner/notes.
- **5 Dynamic App Icon Disguises**: Switch your app launcher icon and label between **Calendar**, **Calculator**, **Quick Notes**, **Clock & Timer**, and **Weather** anytime from Vault Settings.

### 2. 🔐 Secret Date Sequence Lock & Biometric Unlock
- **4-Date Tap Combination**: Unlock the vault by tapping a secret sequence of dates on the calendar in order (e.g. `7 -> 14 -> 21 -> 28`).
- **Biometric Quick Unlock**: Unlock instantly using Fingerprint or Face ID via Android `BiometricPrompt` (`FlutterFragmentActivity` architecture).
- **Discreet Event-Section Trigger**: Quick-tap fingerprint unlock shortcut directly on the calendar event items and headers.

### 3. 🛡️ Reinstallation Survival (Persistent Vault Architecture)
- **Survives App Uninstall & Reinstall**: Sensitive vault files and indexes are mirrored to encrypted persistent storage (`Documents/.calendar_vault/`).
- **No Password Reset Overwrite**: Reinstalling the app detects the existing vault and requires the original password to unlock.
- **Cloud Encrypted Backup & Restore**: Optional encrypted cloud sync to backup and restore your vault anywhere.

### 4. 🖼️ Private Media Gallery & Safe Cleanup
- **Photos & Videos**: Import single or multiple media files with support for JPG, PNG, WEBP, MP4, MOV, and documents.
- **Albums & Favorites**: Create custom albums, move media, favorite items, and sort by date or size.
- **Safe Cleanup of Originals**: Option to automatically verify and delete phone gallery originals with system confirmation so files only exist inside HideX.
- **Permanent Deletion & Vault Wipe**: Securely wipe individual files or perform a complete vault wipe from the Danger Zone.

### 5. 🌐 Private Multi-Engine Browser
- **Normal Browser Experience**: Full Android system back-gesture integration (`PopScope`) — navigating back steps through webpage history naturally.
- **3 Selectable Browser Personas**:
  - 🌐 **Google Chrome**: Official Chrome Mobile User-Agent with Google Search integration.
  - 🦊 **Mozilla Firefox**: Firefox Gecko Mobile User-Agent with DuckDuckGo anti-tracking.
  - ⚡ **UC Browser**: UC Browser Mobile User-Agent with Fast Turbo speed mode and Bing search.
- **Direct Vault Downloads**: Download any image, video, or document directly encrypted into the HideX Vault without leaving traces in public phone storage.

---

## 📂 Project Structure

```
calendar_vault_app/
├── android/                                 # Native Android Kotlin configuration
│   └── app/
│       ├── build.gradle.kts                 # Min SDK 23 (Biometric), Target SDK 34
│       └── src/main/
│           ├── AndroidManifest.xml          # Permissions & 5 Activity-Alias disguises
│           └── kotlin/.../MainActivity.kt  # FlutterFragmentActivity + Icon Switcher channel
├── lib/                                     # Flutter source code
│   ├── main.dart                            # Entry point & theme configuration
│   ├── models/
│   │   ├── album.dart                       # Album model & serialization
│   │   ├── calendar_event.dart              # Decoy calendar event model
│   │   └── vault_item.dart                  # Encrypted vault item model
│   ├── services/
│   │   ├── app_icon_service.dart            # Native app icon switcher
│   │   ├── auth_service.dart                # Secure credential storage & reinstallation guard
│   │   ├── backup_service.dart              # Backup orchestration
│   │   ├── biometric_service.dart           # Local authentication (Fingerprint / Face ID)
│   │   ├── cloud_backup_service.dart        # Remote cloud backup & restore
│   │   ├── encryption_service.dart          # AES-256 encryption & key derivation
│   │   ├── original_media_cleanup_service.dart # Safe original deletion after import
│   │   ├── persistent_storage_service.dart  # Multi-directory persistent storage engine
│   │   ├── sequence_detector_service.dart   # Rolling 4-date tap detector
│   │   ├── theme_service.dart               # Light/Dark mode state
│   │   └── vault_manager.dart               # Vault lifecycle, import/export, wipe
│   └── views/
│       ├── calendar/
│       │   ├── calendar_screen.dart         # Calendar UI with secret triggers
│       │   └── add_event_dialog.dart        # Event creator dialog
│       ├── gallery/
│       │   └── album_detail_screen.dart     # Album contents & management
│       ├── vault/
│       │   ├── app_icon_screen.dart         # Icon disguise selector
│       │   ├── backup_restore_screen.dart   # Cloud & local backup UI
│       │   ├── import_confirmation_dialog.dart # Original deletion confirmation
│       │   ├── photo_viewer_screen.dart     # Secure full-screen photo viewer
│       │   ├── private_browser_screen.dart  # Multi-engine private browser
│       │   ├── sequence_setup_screen.dart   # Change 4-date password sequence
│       │   ├── vault_home_screen.dart       # Main Vault UI, tabs, settings
│       │   └── video_player_screen.dart     # Secure in-app video player
│       └── widgets/
│           └── media_grid_item.dart         # Media thumbnail tile widget
├── test/                                    # Automated test suite
│   ├── password_persistence_test.dart       # 16-test suite covering persistence & wipe
│   ├── vault_upgrade_features_test.dart     # Upgrade features unit tests
│   └── widget_test.dart                     # App smoke tests
├── pubspec.yaml                             # Project dependencies
└── README.md                                # Documentation
```

---

## 🛠️ Building & Running

### 1. Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (v3.24 or higher)
- Android Studio / Android SDK (Platform SDK 34, Build-Tools)
- Java 17

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Run Analysis & Tests
```bash
flutter analyze
flutter test
```

### 4. Build Release APK
```bash
flutter build apk --release
```
The output APK will be placed at:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔒 Security Architecture

| Security Layer | Implementation Details |
|---|---|
| **Encryption Algorithm** | AES-256 in CBC mode with PKCS7 padding |
| **Key Derivation** | SHA-256 cryptographic derivation with unique salt |
| **Authentication** | 4-date tap sequence + BiometricPrompt (Fingerprint/Face) |
| **Hardware Biometrics** | `FlutterFragmentActivity` host with `local_auth` v3 |
| **Persistent Storage** | Multi-directory mirroring to survive app uninstall |
| **Index Integrity Guard** | Data protection guard prevents empty-index overwrites |
| **Decryption in Memory** | Files decrypted in isolated RAM/temp cache and purged on exit |

---
## 📄 License
 
This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
 
## 👤 Developer & Credits
- **Project**: Calendar Hidex App (`com.ankushkumar.calendarvault`)
- **Author**: Ankush Kumar
