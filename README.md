# WinCare Portable v1.1

**Diseñado por DevPoderSEO**

Utilidad portátil en español para **diagnosticar Windows 10/11**, inventariar aplicaciones y componentes, y revisar conexiones de red con una interfaz WinForms basada en Windows PowerShell 5.1.

> **Advertencia importante:** las alertas y etiquetas de riesgo son orientativas. Una IP, proceso o dispositivo desconocido **no demuestra** que exista un intruso. Una firma digital válida **no garantiza** que una aplicación sea segura.

## Instalar en el USB Ventoy

1. En este repositorio selecciona **Code → Download ZIP**.
2. Descomprime todos los archivos en una misma carpeta, por ejemplo `Ventoy:\Herramientas\WinCarePortable\`.
3. Arranca Windows normalmente y ejecuta `INICIAR_WINCARE.bat`.
4. En la ventana principal pulsa **Analizar PC**, o **Seguridad de red e IP** para abrir el diagnóstico de red.

### Permisos de administrador (UAC)

Al abrir WinCare sin elevación, aparecerá una pregunta para **reiniciar WinCare como administrador**. Si aceptas, se muestra el **aviso UAC oficial de Windows**, que debes autorizar personalmente; WinCare no evade la protección de Windows. La ventana sin privilegios se cierra después de abrir la elevada.

Si cancelas o rechazas, WinCare continúa con el inventario **limitado**, sin detenerse ni mostrar como errores las categorías que Windows no permite consultar. Las pestañas **Provisionadas**, **Características** y **Capacidades** necesitan elevación; el botón **Solicitar permisos** permanece disponible para pedirla más tarde. En modo administrador aparece **Admin activo**.

El inicio elevado **no activa las desinstalaciones**: sigue siendo necesario marcar **Habilitar desinstalación** y confirmar cada operación. Si Windows solicita credenciales de **otra cuenta de administrador**, las aplicaciones Appx por usuario se mostrarán para esa cuenta, no para el usuario estándar original.

**Solución manual alternativa:** clic derecho en `INICIAR_WINCARE.bat` → **Ejecutar como administrador**.

**Ventoy no arranca scripts .ps1 ni .bat directamente desde su menú de arranque.** WinCare se ejecuta dentro de una instalación de Windows. No requiere instalador ni altera de forma permanente la política de ejecución de PowerShell.

### Archivos

| Archivo | Función |
|---|---|
| `WinCare.ps1` | Inventario del sistema e interfaz principal |
| `NetworkAudit.ps1` | Diagnóstico de conexiones y seguridad de red (solo lectura) |
| `INICIAR_WINCARE.bat` | Iniciador local |
| `LEEME.txt` | Guía rápida |
| `Red-Confiables.json` | Se genera al registrar equipos de confianza en la misma carpeta o en Reportes |
| `Reportes/` | Inventarios CSV, registros de auditoría y dispositivos registrados |

## Diagnóstico del sistema

- Aplicaciones Microsoft Store (Appx/MSIX) y aprovisionadas.
- Programas Win32 registrados, versión y fabricante.
- Características y capacidades de Windows.
- Servicios y controladores instalados.
- Búsqueda, exportación CSV, registro de auditoría y solicitud de punto de restauración.
- **Solo lectura por defecto**. La eliminación requiere habilitar los cambios y confirmar cada elemento individualmente.
- Solo desinstala aplicaciones Appx expresamente permitidas y MSI identificados y validados.
- Controladores, servicios, Windows Defender, Windows Update y componentes protegidos **nunca se eliminan** desde WinCare.

## Seguridad de red e IP

Pulsa **Seguridad de red e IP** en la ventana principal. Incluye:

1. **Conexiones TCP**: aplicación, PID, IP/puerto local y remoto, estado, tipo de IP (pública/privada), firma digital del ejecutable y avisos de revisión. Una conexión pública sin firma verificable puede aparecer como **Revisar**: no es una detección de malware.
2. **Puertos UDP**: sockets locales, proceso responsable y ruta del ejecutable.
3. **Equipos LAN**: vecinos detectados en la caché ARP/ND de Windows; IP, MAC, interfaz, estado y si el equipo figura en la lista local de reconocidos. No es un escaneo completo de la red.
4. **Configuración IP**: adaptadores, IPv4/IPv6, gateway y servidores DNS.
5. **Firewall**: estado de los perfiles y sus acciones predeterminadas (consulta, sin cambiar reglas).

### Botones de red

- **Actualizar red**: lee nuevamente la información del equipo; no inicia monitoreo continuo.
- **Verificar IP**: valida y clasifica una IPv4/IPv6. Permite enviar **un solo ping** al destino tras confirmación explícita.
- **Ver proceso**: muestra el proceso seleccionado, su ruta y SHA-256 del ejecutable, cuando es accesible. El hash no se envía a ningún tercero.
- **Registrar equipo**: después de verificarlo en tu router, asigna un nombre a la IP/MAC observada. Se guarda localmente en `Red-Confiables.json`. Esto ayuda a distinguir equipos conocidos, pero la MAC puede falsificarse.
- **IP pública**: solo con consentimiento, consulta `https://api.ipify.org?format=json`. El proveedor externo recibe tu IP pública de salida. No se realizan solicitudes externas automáticas.
- **Exportar CSV**: genera archivos locales separados para TCP, UDP, LAN, configuración IP y firewall.

### Cómo investigar una conexión marcada «Revisar»

Comprueba si el proceso es reconocido, verifica la ruta y firma, contrasta el hash con tus herramientas habituales y revisa el destino IP. Si aparece un dispositivo no reconocido en LAN, compara IP/MAC con el panel del router. **No lo consideres intruso únicamente por aparecer en la tabla**. En caso de sospecha real, desconecta el dispositivo afectado según tu procedimiento de respuesta a incidentes y realiza un análisis antivirus actualizado.

### Límites del análisis

- Requiere Windows PowerShell 5.1 y cmdlets de Windows para red (`Get-NetTCPConnection`, `Get-NetUDPEndpoint`, `Get-NetNeighbor`, `Get-NetIPConfiguration`, `Get-NetFirewallProfile`).
- Algunas rutas o datos de procesos pueden no estar disponibles sin elevar privilegios.
- ARP/ND muestra solo vecinos presentes en la caché, no todos los dispositivos conectados al router.
- Los valores de riesgo son heurísticos, sin motor antimalware, detección de paquetes, reputación de IP ni inteligencia de amenazas.
- No ejecuta escaneo masivo, bloqueo de firewall, eliminación de procesos, cambios de DNS, consulta de geolocalización ni desinstalación de controladores.

## Privacidad y cuidado

La recolección y los CSV pueden contener información sensible: IP, procesos y nombres de dispositivos. Evita compartir estos informes públicamente. El proyecto no envía inventarios a servicios externos.

**La desinstalación puede producir pérdida de configuraciones y afectar aplicaciones dependientes.** Realiza copias de seguridad. Los puntos de restauración son opcionales, dependen de Windows y no reemplazan un respaldo.

## Estado de pruebas

Se han revisado los archivos y agregado una verificación automática de sintaxis; **es imprescindible ejecutar pruebas funcionales en Windows 10/11**, especialmente antes de utilizar la desinstalación en equipos de producción. El botón de red no modifica el sistema, salvo los archivos locales que el usuario decide guardar.

---

**WinCare Portable · Diseñado por DevPoderSEO**
