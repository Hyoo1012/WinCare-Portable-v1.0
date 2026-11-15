# WinCare Portable v1.0

Herramienta portátil para inventario y desinstalación **selectiva y conservadora** de aplicaciones en Windows 10/11. Interfaz WinForms en español, compatible con Windows PowerShell 5.1.

> **Advertencia**: eliminar programas puede causar pérdida de configuraciones, datos de la aplicación o funcionalidades dependientes. El nivel de riesgo es orientativo, no una garantía. Haz respaldo de tus datos antes de desinstalar.

## Uso desde Ventoy

1. Descarga el proyecto en GitHub como ZIP y descomprímelo.
2. Copia la carpeta a `Ventoy:\Herramientas\WinCarePortable\`.
3. Inicia Windows normalmente. **No se abre desde el menú de arranque de Ventoy**.
4. Abre la carpeta en el Explorador y ejecuta `INICIAR_WINCARE.bat`.
5. El programa comienza en modo solo lectura; pulsa **Analizar PC** cuando quieras actualizar el inventario.
6. Puedes filtrar, revisar los riesgos y exportar los resultados a CSV.
7. Para desinstalar un elemento permitido, habilita la casilla de cambios y confirma cada operación.

En caso de necesidad, inicia el BAT como administrador para algunas consultas DISM o para solicitar un punto de restauración. No se modifica de forma permanente la política de ejecución de PowerShell.

## Funciones

- Inventario de aplicaciones Appx/MSIX, aplicaciones aprovisionadas y programas Win32 registrados.
- Inventario informativo de características, capacidades, servicios y controladores de Windows.
- Búsqueda, nivel de riesgo, consecuencias y exportación a CSV.
- Auditoría local en `Reportes/auditoria.txt` o, si el USB es de solo lectura, en la carpeta Documentos del usuario.
- Eliminación **solo** para Appx de una lista pequeña de aplicaciones opcionales conocidas y programas MSI identificados por GUID.
- Confirmación individual antes de cada operación.
- Solicitud opcional de punto de restauración (según permisos y configuración de Protección del sistema).

## Protección y límites

- **No** elimina controladores, servicios, características, capacidades, aplicaciones aprovisionadas ni paquetes centrales del sistema.
- **No** desactiva Windows Defender ni Windows Update.
- **No** utiliza `Win32_Product` ni ejecuta comandos `UninstallString` no verificados.
- La desinstalación Appx solo afecta al usuario que ejecuta la herramienta.
- Algunos programas portátiles no aparecen en el registro, y ciertas categorías pueden requerir permisos elevados.
- La clasificación por nombre/fabricante no garantiza detectar todas las dependencias: revisa cada selección.
- No se incluye un instalador ni un ejecutable firmado. El proyecto requiere que PowerShell esté disponible.

## Archivos

- `WinCare.ps1` — código e interfaz gráfica.
- `INICIAR_WINCARE.bat` — iniciador portátil para Windows.
- `LEEME.txt` — instrucciones cortas y advertencias.

## Pruebas

Revisión estática realizada. **No hay pruebas ejecutadas en Windows** en esta entrega. Probar primero en una máquina virtual o equipo de laboratorio antes de usarlo en producción.

## Seguridad

El script se ejecuta localmente y no incluye llamadas a servicios externos. Revisa el código antes de ejecutar herramientas administrativas.
