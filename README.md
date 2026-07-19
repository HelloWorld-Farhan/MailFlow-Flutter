# 📬 MailFlow - The Smart Automated Email Scheduler

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white"/>
  <img src="https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white"/>
  <img src="https://img.shields.io/badge/Google_OAuth-4285F4?style=for-the-badge&logo=google&logoColor=white"/>
  <img src="https://img.shields.io/badge/License-MIT-brightgreen?style=for-the-badge"/>
</p>

<p align="center">
  <strong>MailFlow</strong> is a beautiful, highly polished email scheduling app built in Flutter. It features smart time & date parsing, PDF email extraction, seamless local storage to persist your scheduled history, and custom integrations to send emails automatically exactly when you need them without human interaction.
</p>

---

## ✨ Features

| Feature | Description |
|---|---|
| 🎨 **Perfect UI & Animations** | Modern dark design, smooth bottom sheets, and engaging custom interactions. |
| 🧠 **Smart Input Formatting** | Intelligent date (DD/MM/YYYY) and 12-hour time parsing with strict past-date blocking. |
| 📄 **PDF Email Extraction** | Upload a PDF and the app instantly extracts all valid email addresses using advanced Regex. |
| 💾 **Persistent Local Storage** | Uses SharedPreferences to save your email history permanently on your device. |
| 📧 **Automated Background Sending** | Schedules emails up to 40 per day, prioritizing manual emails over PDF imports. |
| 🌙 **Deep Dark Mode** | A sleek, borderless dark UI that looks phenomenal. |

---

## 📥 How to Download & Run (For Users)

1. Go to the [Releases](https://github.com/HelloWorld-Farhan/MailFlow-Flutter/releases) section of this repository.
2. Download the latest **`app-release.apk`** file.
3. Install it on your Android device.
4. Open **MailFlow**, schedule your emails, and let it handle the automated sending!

---

## 💻 How to Build (For Developers)

Before you begin, ensure you have the **Flutter SDK** installed on your system.

### Step 1 — Clone the Repository
```bash
git clone https://github.com/HelloWorld-Farhan/MailFlow-Flutter.git
cd MailFlow-Flutter
```

### Step 2 — Fetch Dependencies
```bash
flutter pub get
```

### Step 3 — Run Locally
```bash
flutter run
```

### Step 4 — Build the APK Release
```bash
flutter build apk --release
```
*Your `app-release.apk` file will be generated inside `build/app/outputs/flutter-apk/`.*

---

## 👨💻 Author

**Farhan Khalid**  
📧 farhankhalid17968@gmail.com  
🔗 [LinkedIn](https://www.linkedin.com/in/farhan-khalid-117514259/)  
🐙 [GitHub](https://github.com/HelloWorld-Farhan)  

---

## 📄 License

```text
MIT License

Copyright (c) 2026 Farhan Khalid

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

## 🌟 Support

If you found this app helpful for managing your email campaigns, please consider giving it a ⭐ on GitHub!

<p align="center">Made with ❤️ in India</p>
