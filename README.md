# WinCare Portable v1.3

**Diseñado por DevPoderSEO**

Utilidad portátil en español para **diagnosticar Windows 10/11**, inventariar aplicaciones y componentes, consultar hardware/salud del equipo y revisar conexiones de red con una interfaz WinForms basada en Windows PowerShell 5.1.

> **Advertencia importante:** las alertas y etiquetas de riesgo son orientativas. Una IP, proceso o dispositivo desconocido **no demuestra** que exista un intruso. Una firma digital válida **no garantiza** que una aplicación sea segura.

## Instalar en el USB Ventoy

1. En este repositorio selecciona **Code → Download ZIP**.
2. Descomprime todos los archivos en una misma carpeta, por ejemplo `Ventoy:\Herramientas\WinCarePortable\`.
3. Arranca Windows normalmente y ejecuta `INICIAR_WINCARE.bat`.
4. En la ventana principal pulsa **Analizar PC**, **Seguridad de red e IP** o **Hardware y salud** o **Mantenimiento** para abrir el módulo deseado.

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
| `HardwareAudit.ps1` | Inventario de componentes, estado de discos, dispositivos y accesos a herramientas de Windows (solo lectura) |
| `MaintenanceAudit.ps1` | Diagnóstico preventivo, limpieza selectiva de temporales y verificaciones opcionales |
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

## Hardware y salud (similar a msinfo32)

Pulsa **Hardware y salud** en la ventana principal. El inventario se organiza en once secciones: **Resumen, Procesador, Memoria RAM, Placa y BIOS, Discos, Unidades, Gráficos, Red, Batería, Dispositivos e Incidencias**.

- **Procesador**: modelo, fabricante, núcleos, hilos, frecuencia indicada por firmware y cachés.
- **Memoria**: capacidad total, módulos, ranuras reportadas, velocidad y fabricante cuando SMBIOS proporciona esos datos.
- **Placa/BIOS**: fabricante, modelo y versión de firmware; estado consultable de Secure Boot y TPM.
- **Discos y unidades**: capacidad, tipo, estado reportado, espacio libre. Temperatura, horas y contadores de fiabilidad solo si los proporciona el hardware y los controladores.
- **Gráficos**: GPU, versión de controlador y resolución cuando están disponibles.
- **Red**: adaptadores, estado y velocidad reportada.
- **Batería**: detección y carga estimada en portátiles compatibles.
- **Dispositivos**: inventario Plug and Play y códigos del Administrador de dispositivos.
- **Incidencias**: dispositivos con códigos no cero y hasta 20 eventos críticos/de error registrados en el sistema en los últimos 7 días; son hechos históricos para revisar, no diagnósticos definitivos.

La herramienta conserva el **modo solo lectura**; no ejecuta pruebas de estrés, no cambia BIOS, no actualiza firmware, no instala drivers ni modifica particiones. En unidades con poca capacidad libre o estado de salud no normal, recomienda revisión; **no garantiza detectar fallos inminentes**. Algunos discos no exponen SMART/temperatura. En Windows la información de WMI/CIM depende del fabricante y puede ser parcial o inexacta.

### Herramientas Windows incluidas

En **Hardware y salud**, elige la herramienta en el selector y pulsa **Abrir herramienta**:

| Herramienta | Función |
|---|---|
| Información del sistema (`msinfo32`) | Detalle completo de componentes e información del sistema |
| Diagnóstico DirectX (`dxdiag`) | Video, audio, DirectX y controladores |
| Administrador de dispositivos (`devmgmt.msc`) | Revisar componentes y controladores |
| Monitor de recursos (`resmon`) | CPU, memoria, disco y red en tiempo real |
| Monitor de rendimiento (`perfmon`) | Contadores y rendimiento |
| Visor de eventos (`eventvwr.msc`) | Errores y eventos del sistema |
| Monitor de confiabilidad (`perfmon /rel`) | Historial de errores y estabilidad |
| Administrador de tareas (`taskmgr`) | Procesos y consumo |
| Administración de discos (`diskmgmt.msc`) | Acceso con advertencia a una herramienta que puede modificar discos |

**Precaución:** WinCare únicamente abre estas herramientas. Algunas permiten cambios importantes por cuenta propia; administrar particiones sin un respaldo puede causar pérdida de datos.

Pulsa **Exportar informe** para guardar los hallazgos en CSV por categoría, dentro de `Reportes/hardware-AAAAMMDD-HHMMSS/` (o Documentos si el USB es de solo lectura). Los reportes pueden incluir nombres del equipo, adaptadores y otros datos técnicos: revísalos antes de compartir.

## Centro de mantenimiento y limpieza segura (v1.3)

En la ventana principal pulsa **Mantenimiento**. El módulo es portátil y separa tres pestañas:

### Diagnóstico preventivo

Inspección del antivirus/Defender, registro informativo de productos de seguridad, estado del servicio Windows Update, último hotfix registrado, espacio libre de unidades, aplicaciones de inicio, firewall y versión de Windows. Los resultados se clasifican como **Correcto**, **Revisar**, **Información** y **No verificadas**. Son indicadores orientativos: una entrada de inicio o servicio detenido no prueba malware ni fallos. La herramienta no comprueba automáticamente actualizaciones pendientes.

### Limpieza segura

Solo busca archivos con las extensiones **.tmp, .temp, .cache, .bak y .old** dentro de **LOCALAPPDATA\Temp** (más de 7 días) y **Windows\Temp** (más de 14 días; requiere administrador). El escaneo no elimina nada, y muestra ruta, tamaño y fecha de cada candidato.

- El usuario selecciona los archivos y marca la confirmación de respaldo.
- Exige confirmación final; si se incluye Windows\Temp, pide una confirmación adicional.
- Verifica nuevamente la ubicación autorizada, antigüedad, extensión, tamaño y fechas antes de borrar.
- Excluye rutas externas, reparse points, junctions y enlaces simbólicos; ignora archivos bloqueados o cambiados desde la vista previa.
- No elimina carpetas con recursión y no borra archivos ajenos a las extensiones aprobadas.
- Omite rutas de navegadores, ejecutables, registros del sistema y archivos importantes.
- La exploración está limitada a **30.000 entradas por carpeta** y profundidad 12; informa si se alcanza el límite.
- Muestra archivos eliminados, omitidos y errores. **La eliminación no se puede revertir de forma garantizada.**

El resultado ocupa solamente parte del almacenamiento temporal: no elimina datos personales ni intenta limpiar todo Windows indiscriminadamente. Cierra las aplicaciones antes de limpiar y conserva respaldos.

### Herramientas de mantenimiento

Accesos oficiales a Windows Update, Aplicaciones de inicio, Sensor de almacenamiento, Seguridad de Windows y carpetas de reportes.

- **SFC /verifyonly** y **DISM /Online /Cleanup-Image /ScanHealth** se ejecutan manualmente tras confirmación, en una consola aparte con solicitud UAC. Son verificaciones, no reparaciones.
- **Vaciar Papelera** es opcional y está separado de la limpieza temporal. Exige doble confirmación explícita. El programa no estima previamente el contenido ni puede garantizar su recuperación.

**Nunca borra:** Descargas, Documentos, archivos personales, Prefetch, WinSxS, caché de Windows Update, Defender, DriverStore, perfiles de navegador, drivers, servicios, registro o componentes protegidos. No existe limpieza automática o programada.

Los resultados se exportan a CSV en Reportes/mantenimiento-AAAAMMDD-HHMMSS. Los registros de auditoría se guardan localmente en auditoria.txt o auditoria-mantenimiento.txt. Los informes pueden contener datos técnicos privados del equipo.

**Limitaciones:** cierto inventario y Windows\Temp requieren permisos elevados. La limpieza no reemplaza un respaldo y no detecta todos los problemas del computador. Las pruebas automatizadas verifican sintaxis, construcción de interfaz y exclusión de rutas/extensiones, no borrados reales de producción. Comprueba la operación en un equipo de prueba antes de utilizarla en equipos importantes.

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

El proyecto incorpora validación automática de sintaxis y pruebas de construcción de interfaces en GitHub Actions. **Faltan pruebas funcionales con hardware real en Windows 10/11**, especialmente antes de utilizar desinstalaciones en producción. El módulo de hardware solo consulta el sistema y abre herramientas elegidas expresamente; los reportes se guardan localmente cuando se solicita exportación.

---

**WinCare Portable · Diseñado por DevPoderSEO**
