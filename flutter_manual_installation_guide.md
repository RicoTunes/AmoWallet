# MANUAL FLUTTER SDK INSTALLATION GUIDE

## OPTION 1: Download Fresh Flutter SDK

### Step 1: Download Flutter SDK
1. Go to: https://flutter.dev/docs/get-started/install/windows
2. Download the latest stable version (currently 3.22.0)
3. Save to: `C:\Users\RICO\ricoamos\flutter-sdk`

### Step 2: Extract Manually
1. Right-click on `flutter.zip` → "Extract All..."
2. Choose destination: `C:\Users\RICO\ricoamos\flutter-sdk`
3. Make sure the structure is: `flutter-sdk\flutter\bin\flutter.bat`

### Step 3: Set Environment Variables
1. Open Windows Search → Type "Environment Variables"
2. Click "Edit the system environment variables"
3. Click "Environment Variables" button
4. Under "System Variables", find "Path" and click "Edit"
5. Click "New" and add: `C:\Users\RICO\ricoamos\flutter-sdk\flutter\bin`
6. Click "OK" to save all changes

### Step 4: Verify Installation
Open new Command Prompt or PowerShell and run:
```cmd
flutter --version
```

## OPTION 2: Use Chocolatey (Recommended)

### Step 1: Install Chocolatey
Open PowerShell as Administrator and run:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

### Step 2: Install Flutter
```powershell
choco install flutter
```

### Step 3: Verify Installation
```powershell
flutter --version
```

## OPTION 3: Git Clone Method

### Step 1: Install Git First
Download from: https://git-scm.com/download/win

### Step 2: Clone Flutter
```cmd
git clone https://github.com/flutter/flutter.git -b stable flutter-sdk
```

### Step 3: Set Environment Variables
Same as Option 1, Step 3

## TESTING THE FRONTEND

Once Flutter is installed:

### Step 1: Navigate to Frontend Directory
```cmd
cd crypto-wallet-app\frontend
```

### Step 2: Get Dependencies
```cmd
flutter pub get
```

### Step 3: Run the App
```cmd
flutter run
```

## TROUBLESHOOTING

### If Flutter Command Not Found:
- Restart your terminal/Command Prompt
- Verify environment variables are set correctly
- Try running: `refreshenv` in PowerShell

### If Dependencies Fail:
```cmd
flutter doctor
```
This will diagnose any missing dependencies.

### For Android Development:
- Install Android Studio
- Set up Android SDK
- Enable developer options on your device

### For iOS Development (Mac only):
- Install Xcode
- Set up iOS simulator

## QUICK START AFTER INSTALLATION

1. Install Flutter using any method above
2. Run: `flutter doctor` to check setup
3. Navigate to: `crypto-wallet-app\frontend`
4. Run: `flutter pub get`
5. Run: `flutter run` to start the app

The backend is already running on port 3000, so the Flutter app should connect automatically.