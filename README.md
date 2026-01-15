# Qingping Air Monitor

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

A native macOS menu bar app for monitoring air quality data from **Qingping Air Monitor Lite** devices. View real-time CO₂, PM2.5, PM10, temperature, and humidity readings directly from your menu bar.

## Features

- **Menu Bar Integration** — Lives in your menu bar, always one click away
- **Real-time Monitoring** — CO₂, PM2.5, PM10, temperature, humidity, and battery level
- **Air Quality Indicators** — Color-coded levels (Good, Moderate, Poor, Very Poor)
- **Customizable Display** — Choose which metrics to show in the menu bar
- **Multiple Devices** — Support for multiple Qingping devices on your account
- **Auto-refresh** — Configurable refresh intervals (1, 5, 15, or 30 minutes)
- **Network Aware** — Automatic reconnection when network becomes available
- **Wake Detection** — Auto-refresh after your Mac wakes from sleep
- **Secure** — Credentials stored in macOS Keychain, sandboxed app

## Screenshots

```
┌─────────────────────────────────┐
│ 🌡️ 23.5°  💧 45%  CO₂ 650ppm   │  ← Menu bar
└─────────────────────────────────┘

┌─────────────────────────────────┐
│  Qingping Air Monitor      🟢  │
│  Living Room                    │
├─────────────────────────────────┤
│  💨 CO₂        650 ppm    Good │
│  🌫️ PM2.5      8 µg/m³    Good │
│  🌫️ PM10       12 µg/m³   Good │
│  ─────────────────────────────  │
│  🌡️ 23.5°C    💧 45%           │
│  🔋 85%       Updated 2m ago   │
├─────────────────────────────────┤
│  ↻  📱  ⚙️           Quit      │
└─────────────────────────────────┘
```

## Requirements

- macOS 14.0 (Sonoma) or later
- Qingping Air Monitor Lite device
- Qingping Developer API credentials

## Installation

### Option 1: Download Release
Download the latest `.dmg` from [Releases](../../releases) and drag to Applications.

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/qingping-air-monitor.git
cd qingping-air-monitor

# Open in Xcode
open QingpingAirMonitor/QingpingAirMonitor.xcodeproj

# Build and run (⌘R)
```

## Configuration

### 1. Get API Credentials

1. Go to [developer.qingping.co](https://developer.qingping.co)
2. Create an account or sign in
3. Create a new application
4. Copy your **App Key** (Client ID) and **App Secret** (Client Secret)

### 2. Configure the App

1. Launch Qingping Air Monitor
2. Click the menu bar icon → **Settings** (⚙️)
3. In the **API** tab, enter your credentials
4. Click **Save**

The app will automatically connect and start displaying your air quality data.

## Usage

### Menu Bar Display

Customize what appears in your menu bar:
1. Open **Settings** → **Display** tab
2. Toggle the metrics you want to see:
   - Temperature
   - Humidity
   - CO₂
   - PM2.5
   - PM10

### Refresh Interval

Set how often the app fetches new data:
1. Open **Settings** → **General** tab
2. Select your preferred interval

> **Note:** Qingping devices upload data every 15 minutes by default. Setting a shorter refresh interval won't provide more frequent data updates.

### Multiple Devices

If you have multiple Qingping devices:
1. Click the device switcher icon (📱) in the menu bar panel
2. Select the device you want to monitor

## Air Quality Levels

| Metric | Good | Moderate | Poor | Very Poor |
|--------|------|----------|------|-----------|
| CO₂ | < 800 ppm | 800-1000 | 1000-1500 | > 1500 |
| PM2.5 | < 12 µg/m³ | 12-35 | 35-55 | > 55 |
| PM10 | < 54 µg/m³ | 54-154 | 154-254 | > 254 |

## Architecture

```
QingpingAirMonitor/
├── App/
│   ├── QingpingAirMonitorApp.swift    # App entry point
│   └── Info.plist
├── Managers/
│   └── AppState.swift                  # Global state management
├── Models/
│   ├── AirQualityData.swift           # Air quality data model
│   ├── Device.swift                    # Device models
│   ├── MenuBarDisplayOptions.swift    # Display preferences
│   └── TokenResponse.swift            # OAuth response
├── Services/
│   ├── AuthenticationService.swift    # OAuth 2.0 authentication
│   ├── KeychainService.swift          # Secure credential storage
│   └── QingpingAPIService.swift       # API communication
└── Views/
    ├── MenuBarView.swift              # Main menu bar panel
    ├── SettingsView.swift             # Settings window
    └── SensorRowView.swift            # Sensor display components
```

### Key Technologies

- **SwiftUI** — Modern declarative UI framework
- **Swift Concurrency** — async/await, actors for thread safety
- **Keychain Services** — Secure credential storage
- **Network Framework** — Connectivity monitoring
- **OAuth 2.0** — Secure API authentication

## Security

- ✅ App Sandbox enabled
- ✅ Credentials stored in macOS Keychain
- ✅ No sensitive data in logs
- ✅ Network timeouts configured
- ✅ Input validation on credentials
- ✅ MAC addresses obfuscated in UI

## Development

### Requirements

- Xcode 15.0+
- macOS 14.0+ SDK

### Building

```bash
# Clone
git clone https://github.com/yourusername/qingping-air-monitor.git

# Build via command line
cd qingping-air-monitor/QingpingAirMonitor
xcodebuild -scheme QingpingAirMonitor -configuration Release build
```

### Project Structure

The app follows the **MVVM-S** (Model-View-ViewModel-Service) architecture:

- **Models** — Data structures and business logic
- **Views** — SwiftUI views
- **Managers** — AppState acts as the ViewModel
- **Services** — Network, authentication, and storage services

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Qingping](https://www.qingping.co/) for their air quality monitoring devices
- [Qingping Developer Portal](https://developer.qingping.co) for the API documentation

## Support

If you encounter any issues or have questions:

1. Check the [Issues](../../issues) page
2. Create a new issue with details about your problem
3. Include your macOS version and app version

---

<p align="center">
  Made with ❤️ for cleaner air
</p>
