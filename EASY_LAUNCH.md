# Compilación y Easy Launch de LimoMada3DS en Windows

Este flujo usa el MinGW incluido con CLion, CMake, Ninja y los submodulos del propio proyecto. No descarga ROMs, claves ni firmware.

## Terminal

Desde la raiz del repositorio:

```powershell
.\scripts\Check-Dependencies.ps1
.\scripts\Build-Lime3DS.ps1 -Bundle
.\scripts\Create-DesktopShortcut.ps1
```

`-CleanConfigure` fuerza una configuracion limpia de CMake. El primer configure puede descargar Qt 6.7.2, tal como lo define el CMake original.

## CLion

Abre esta carpeta como proyecto. CLion detecta `CMakePresets.json`; selecciona `windows-mingw-relwithdebinfo` y configura como toolchain el MinGW incluido con CLion. La configuración compartida `LimoMada3DS` queda disponible en la barra superior: selecciónala y pulsa **Run**; CLion construirá el target técnico `lime` antes de iniciar `limomada3ds.exe` y usará las DLL del paquete `bundle`. Ejecuta al menos una vez `.\scripts\Build-Lime3DS.ps1 -Bundle` después de una configuración limpia para crear esas dependencias.

## Easy Launch

Ejecuta `.\scripts\Easy-Launch.ps1`. Busca `limomada3ds.exe`, abre un selector limitado a `.3ds`, recuerda el último archivo en `%LOCALAPPDATA%\LimoMada3DS-EasyLaunch\settings.json` y lo inicia. Si existe la configuración anterior de Lime3DS, la migra automáticamente. Usa `-ForgetLastGame` para volver a mostrar el selector, o `-NoRemember` para elegir sin leer ni guardar el último juego. El acceso directo ejecuta el mismo script.

LimoMada3DS puede requerir archivos del sistema extraídos legalmente de tu propia consola. Consulta la documentación incluida/original de Lime3DS y colócalos en el directorio de usuario que LimoMada3DS abre desde su menú; este repositorio no incluye ni obtiene ROMs, claves o firmware.

La licencia GPL y los avisos originales permanecen en `license.txt` y en sus archivos fuente.
