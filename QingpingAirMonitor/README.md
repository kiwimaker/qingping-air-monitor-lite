# Qingping Air Monitor - macOS Menu Bar App

Una aplicación de barra de menú para macOS que muestra los datos de tu **Qingping Air Monitor Lite** en tiempo real.

## Características

- **Menu Bar nativo**: Icono discreto en la barra de menú con el valor de CO2
- **Datos completos**: CO2, PM2.5, PM10, temperatura y humedad
- **Indicadores de calidad**: Colores que indican el nivel de calidad del aire
- **Actualización automática**: Configurable entre 30 segundos y 15 minutos
- **Multi-dispositivo**: Soporte para múltiples monitores Qingping

## Requisitos

- macOS 13 Ventura o superior
- Qingping Air Monitor Lite configurado en modo Qingping+ (no HomeKit)
- Credenciales de API de Qingping

## Configuración

### 1. Obtener credenciales de API

1. Ve a [developer.qingping.co](https://developer.qingping.co)
2. Crea una cuenta de desarrollador
3. En **Access Management**, crea una nueva aplicación
4. Copia el **App Key** (Client ID) y **App Secret** (Client Secret)

### 2. Configurar tu dispositivo

Asegúrate de que tu Qingping Air Monitor Lite esté:
- Conectado a Wi-Fi
- Configurado en modo **Qingping+** (no HomeKit)
- Vinculado a tu cuenta de Qingping en la app Qingping+

### 3. Ejecutar la app

```bash
cd QingpingAirMonitor
open QingpingAirMonitor.xcodeproj
```

En Xcode, presiona **⌘R** para ejecutar la app.

### 4. Configurar credenciales en la app

1. Haz clic en el icono de la app en la barra de menú
2. Abre **Ajustes** (icono de engranaje)
3. Introduce tu App Key y App Secret
4. Haz clic en **Guardar**

## Compilar desde terminal

```bash
cd QingpingAirMonitor

# Generar proyecto (requiere xcodegen)
xcodegen generate

# Compilar
xcodebuild -project QingpingAirMonitor.xcodeproj \
  -scheme QingpingAirMonitor \
  -configuration Release \
  build

# La app compilada estará en:
# ~/Library/Developer/Xcode/DerivedData/QingpingAirMonitor-*/Build/Products/Release/
```

## Estructura del proyecto

```
QingpingAirMonitor/
├── App/
│   ├── QingpingAirMonitorApp.swift  # Entry point
│   └── Info.plist
├── Views/
│   ├── MenuBarView.swift            # Vista principal
│   ├── SensorRowView.swift          # Fila de sensor
│   └── SettingsView.swift           # Ajustes
├── Models/
│   ├── AirQualityData.swift         # Datos de calidad
│   ├── Device.swift                 # Modelo de dispositivo
│   └── TokenResponse.swift          # Respuesta OAuth
├── Services/
│   ├── QingpingAPIService.swift     # Cliente API
│   ├── AuthenticationService.swift  # OAuth2
│   └── KeychainService.swift        # Almacenamiento seguro
└── Managers/
    └── AppState.swift               # Estado global
```

## API de Qingping

La app usa la API Cloud de Qingping:
- **OAuth2**: `https://oauth.cleargrass.com/oauth2/token`
- **Devices**: `https://apis.cleargrass.com/v1/apis/devices`

## Licencia

MIT
