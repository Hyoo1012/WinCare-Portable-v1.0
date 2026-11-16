# WinCare Portable v1.9

**Diseñado por DevPoderSEO**

Utilidad portátil en español para **diagnosticar Windows 10/11**, inventariar aplicaciones y componentes, consultar hardware/salud del equipo y revisar conexiones de red con una interfaz WinForms basada en Windows PowerShell 5.1.

> **Advertencia importante:** las alertas y etiquetas de riesgo son orientativas. Una IP, proceso o dispositivo desconocido **no demuestra** que exista un intruso. Una firma digital válida **no garantiza** que una aplicación sea segura.

## Instalar en el USB Ventoy

1. En este repositorio selecciona **Code → Download ZIP**.
2. Descomprime todos los archivos en una misma carpeta, por ejemplo `Ventoy:\Herramientas\WinCarePortable\`.
3. Arranca Windows normalmente y ejecuta `INICIAR_WINCARE.bat`.
4. Elige uno de los **siete módulos**: Hardware y salud, Red e IP, Mantenimiento, Taller técnico, Recomendaciones, Soporte PC o CCTV/NVR.

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
| `AppRules.ps1` | Motor de reglas portátiles de programas Conservar/Opcional |
| `AppRecommendations.ps1` | Editor visual para el catálogo de aplicaciones |
| `TechToolkit.ps1` | Informe técnico HTML/CSV, respaldo de drivers y reparación guiada |
| NetworkDiagnostics.ps1 | Diagnóstico inteligente de IP, DHCP, DNS, Internet, Wi-Fi y LAN autorizada |
| NetworkDiagnosticsCore.ps1 | Reglas estrictas de IPv4, subredes y alcance de sondeo LAN |
| SupportTechnician.ps1 | Soporte v1.7: impresoras, eventos Windows, inicio, respaldos e intervenciones |
| CCTVCore.ps1 | Catálogo portátil validado y reglas de seguridad de dispositivos CCTV |
| CCTVAudit.ps1 | CCTV v1.8: inventario, mapa lógico y diagnóstico limitado de cámaras/NVR/DVR |
| DesktopUninstall.ps1 | Desinstalación segura Steam, MSI y asistente interactivo con restricciones |
| `Configuracion/recomendaciones.json` | Se crea al guardar la primera regla y se puede copiar con Ventoy |
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

## Centro de mantenimiento y limpieza segura (v1.4)

En la ventana principal pulsa **Mantenimiento**. El módulo es portátil y separa tres pestañas:

### Diagnóstico preventivo

Inspección del antivirus/Defender, registro informativo de productos de seguridad, estado del servicio Windows Update, último hotfix registrado, espacio libre de unidades, aplicaciones de inicio, firewall y versión de Windows. Los resultados se clasifican como **Correcto**, **Revisar**, **Información** y **No verificadas**. Son indicadores orientativos: una entrada de inicio o servicio detenido no prueba malware ni fallos. La herramienta no comprueba automáticamente actualizaciones pendientes.

### Limpieza segura

La limpieza se realiza **por categoría**, cada una con sus propias condiciones. El selector muestra una categoría a la vez y **Escanear categoría** identifica los candidatos sin borrar ninguno.

| Categoría | Archivos permitidos | Antigüedad | Precaución |
|---|---|---|---|
| Temporales del usuario | .tmp, .temp, .cache, .bak, .old dentro de LocalAppData\\Temp | 7 días | Algunas aplicaciones pueden necesitar reconstruir temporales |
| Temporales de Windows | Mismas extensiones dentro de Windows\\Temp | 14 días | Requiere administrador y confirmación adicional |
| Volcados de errores | .dmp y .mdmp dentro de LocalAppData\\CrashDumps | 30 días | Se perderán evidencias para diagnosticar cierres inesperados |
| Informes de errores archivados | .wer, .dmp, .mdmp, .hdmp en ProgramData\\Microsoft\\Windows\\WER\\ReportArchive | 45 días | Requiere administrador; conserva informes necesarios para soporte |
| Caché de miniaturas | thumbcache_*.db dentro del directorio Explorer del usuario | 14 días | Windows puede regenerarla; ficheros en uso se omiten |

**Uso de la limpieza:** selecciona una categoría → **Escanear categoría** → marca archivos o **Seleccionar todos** → marca **He revisado los archivos y tengo respaldo** → **Limpiar seleccionados** → confirma el resumen. El botón se habilita cuando hay archivos seleccionados y, si falta autorización, muestra qué casilla debes marcar. Cambiar de categoría descarta la selección anterior para impedir mezclas.

**No se recomienda seleccionar automáticamente todas las categorías.** Los volcados y reportes de errores pueden ser importantes cuando investigas una avería.

- El usuario selecciona archivos de **una categoría a la vez** y marca explícitamente la confirmación de respaldo.
- Exige confirmación final; en carpetas de Windows e informes archivados, pide una confirmación adicional.
- Verifica nuevamente la ubicación autorizada, antigüedad, extensión, tamaño y fechas antes de borrar.
- Excluye rutas externas, reparse points, junctions y enlaces simbólicos; ignora archivos bloqueados o cambiados desde la vista previa.
- No elimina carpetas con recursión y no borra archivos ajenos a las extensiones aprobadas.
- Omite rutas de navegadores, ejecutables, registros del sistema y archivos importantes.
- La exploración está limitada a **30.000 entradas por carpeta** y profundidad 12; informa si se alcanza el límite.
- Muestra archivos eliminados, omitidos y errores. **La eliminación no se puede revertir de forma garantizada.**

El resultado ocupa solamente parte del almacenamiento temporal: no elimina datos personales ni intenta limpiar todo Windows indiscriminadamente. Cierra las aplicaciones antes de limpiar y conserva respaldos.

### Herramientas de mantenimiento

Accesos oficiales a Windows Update, Aplicaciones de inicio, Sensor de almacenamiento, Seguridad de Windows y carpetas de reportes. También incluye **Liberador de espacio**, **Servicios**, **Tareas programadas**, **Visor de eventos**, **msconfig** y **Monitor de recursos** para que el técnico pueda abrir herramientas de Windows rápidamente. Son aplicaciones externas que pueden ofrecer cambios por cuenta propia, no ejecutados automáticamente por WinCare.

- **SFC /verifyonly** y **DISM /Online /Cleanup-Image /ScanHealth** se ejecutan manualmente tras confirmación, en una consola aparte con solicitud UAC. Son verificaciones, no reparaciones.
- **Vaciar Papelera** es opcional y está separado de la limpieza temporal. Exige doble confirmación explícita. El programa no estima previamente el contenido ni puede garantizar su recuperación.

**Otras acciones individuales para técnicos:** **Vaciar caché DNS** usa el mecanismo oficial de Windows y solo se ejecuta después de confirmar; limpia memoria de resolución, no espacio de disco. **Caché Microsoft Store** abre `wsreset.exe` tras autorización, que permite reiniciar la caché de Store sin desinstalar aplicaciones. Ninguna de estas acciones se ejecuta durante el escaneo. Si faltan permisos o herramientas nativas, se muestra el error.

**Nunca borra:** Descargas, Documentos, archivos personales, Prefetch, WinSxS, caché de Windows Update, Defender, DriverStore, perfiles de navegador, drivers, servicios, registro o componentes protegidos. No existe limpieza automática o programada.

Los resultados se exportan a CSV en Reportes/mantenimiento-AAAAMMDD-HHMMSS. Los registros de auditoría se guardan localmente en auditoria.txt o auditoria-mantenimiento.txt. Los informes pueden contener datos técnicos privados del equipo.

**Limitaciones:** cierto inventario y Windows\Temp requieren permisos elevados. La limpieza no reemplaza un respaldo y no detecta todos los problemas del computador. Las pruebas automatizadas verifican sintaxis, construcción de interfaz y exclusión de rutas/extensiones, no borrados reales de producción. Comprueba la operación en un equipo de prueba antes de utilizarla en equipos importantes.

## Desinstalación de programas y juegos — v1.9

Antes, WinCare solo activaba el botón para aplicaciones Store opcionales y MSI. En la versión 1.9 **también se admiten juegos de Steam y asistentes de desinstalación interactivos verificados**, y el resto de los programas puede abrirse desde la configuración oficial de Windows.

**Dota 2 desde WinCare:**

1. Abre WinCare, pulsa **Analizar PC** y ve a la pestaña **Programas**.
2. Busca **Dota 2** y selecciónalo.
3. Si Windows lo registró como **Steam App 570**, verás **Steam** en Acción y **Desinstalar con Steam** en el botón inferior.
4. Marca **Permitir desinstalación (con advertencia)** arriba de la tabla.
5. Haz clic en **Desinstalar con Steam**, revisa la advertencia y confirma. WinCare inicia el cliente Steam con la solicitud correspondiente al AppID 570, **sin borrar los archivos manualmente**.
6. Completa el proceso en Steam y vuelve a pulsar **Analizar PC** al finalizar.

**Si Dota 2 no aparece en Programas**, utiliza el nuevo botón **Abrir Steam / juegos** en la zona superior. En la Biblioteca de Steam haz clic derecho en Dota 2 → **Administrar → Desinstalar** y confirma. Steam es el responsable final de quitar los archivos del juego; WinCare no afirma que se haya eliminado solo por abrirlo.

**Otros métodos:** Appx opcional (usuario actual), MSI por GUID revalidado, asistente interactivo con nombre y ubicación permitidos y firma digital válida, o el botón **Abrir en Windows** para finalizar allí el proceso. Nunca se ejecutan las cadenas arbitrarias de UninstallString ni los argumentos de desinstalación silenciosa. Los componentes de Windows, drivers y aplicaciones marcadas **Conservar** continúan protegidos. No hay desinstalación masiva.

**Precaución:** quitar juegos y aplicaciones puede eliminar partidas guardadas localmente, archivos propios del programa, configuraciones o funciones dependientes. Haz respaldo y cierra los programas antes.

## Limpieza segura: corrección del botón invisible

En **03 Mantenimiento → Limpieza segura**, la barra superior de acciones se reorganizó con un diseño adaptable: **Escanear categoría**, **Seleccionar todos**, **Desmarcar**, casilla de autorización y botón rojo **Limpiar seleccionados**. El listado ahora ocupa una fila independiente y no puede desplazar el botón fuera del panel cuando cambie el tamaño de la ventana.

1. Elige **Temporales del usuario** u otra categoría y pulsa **Escanear categoría**.
2. Revisa los archivos encontrados, sus rutas, antigüedad y tamaño. Marca solo los que quieres quitar (o **Seleccionar todos**).
3. Marca **He revisado los archivos y tengo respaldo si lo necesito**.
4. Pulsa **Limpiar seleccionados** y confirma. Solo entonces WinCare revalida cada archivo y elimina aquellos que todavía cumplan las reglas.

Los archivos abiertos, modificados o inaccesibles se omiten. La limpieza no elimina carpetas completas ni se inicia automáticamente. Las pruebas automatizadas verifican que el botón esté en la barra visible y que seleccionar y desmarcar cambien su disponibilidad. La eliminación real requiere una prueba manual autorizada.

## Recomendaciones personalizadas: qué conservar y qué desinstalar

El técnico puede crear un **catálogo portátil** desde la nueva sección **05 Recomendaciones**, sin modificar scripts:

1. En la pantalla principal, selecciona una aplicación de **Apps Store** o **Programas**.
2. Abre **05 Recomendaciones**. Se completarán nombre, fabricante y tipo desde la selección, cuando sea posible.
3. Selecciona **Conservar** (bloquea la desinstalación desde WinCare) u **Opcional** (solo recomendación de revisión; no autoriza una eliminación).
4. Escribe el motivo de la recomendación y pulsa **Guardar recomendación**.
5. Al cerrar el editor, WinCare actualiza la columna **Recomendación**. Selecciona una regla existente para modificarla o quitarla. Puedes exportar el catálogo como CSV.

Las reglas se guardan en `Configuracion/recomendaciones.json`, junto al programa; se crea un archivo `.bak` antes de reemplazar la configuración. Appx coincide por nombre exacto; Win32 por nombre y fabricante exactos. El archivo puede copiarse a otra memoria Ventoy. **Si es ilegible, WinCare desactiva la desinstalación por seguridad**.

**Regla clave:** marcar un elemento como **Opcional** NUNCA desbloquea Defender, drivers, Windows Update, Store, WebView, .NET ni otros componentes protegidos. Algunas aplicaciones solo pueden retirarse con la configuración oficial de Windows. Una recomendación del técnico no representa una certificación de seguridad.

## Taller técnico: informes, controladores y reparación guiada

Pulsa **04 Taller técnico** para acceder a tres secciones:

- **Informe técnico:** lee Windows, CPU, RAM, discos, GPU, dispositivos con códigos de error, red, firewall, Defender y datos de Windows Update. Incluye cliente y orden de trabajo. La opción de incluir identificadores del equipo e IP está **desactivada por defecto**. Exporta un HTML imprimible como PDF en un navegador y un CSV, sin conexiones externas.
- **Respaldo de drivers:** utiliza la herramienta nativa `pnputil /export-driver *` para guardar controladores de terceros en una carpeta elegida y confirmada por el usuario. Requiere privilegios administrativos. No respalda programas, licencias, datos personales ni una imagen completa de Windows; es recomendable una unidad externa.
- **Reparación guiada:** ofrece verificaciones SFC `/verifyonly`, DISM `/ScanHealth` y CHKDSK `/scan` y, separadamente, reparaciones opcionales SFC `/scannow` y DISM `/RestoreHealth` con **doble confirmación**. Muestra avisos de riesgo y utiliza el UAC de Windows. Ninguna reparación se ejecuta automáticamente y **no se garantiza reversibilidad**.

El informe se guarda en una subcarpeta `Reportes/taller-AAAAMMDD-HHMMSS/`. Revísalo antes de entregarlo: puede contener información del cliente si la ingresaste.

## Interfaz v1.5

La pantalla principal separa los cinco módulos en una barra de navegación superior y deja las operaciones sensibles en una fila inferior. Se amplió el espacio del inventario, se añadió la columna **Recomendación** y se usan etiquetas, colores y ayudas contextuales para facilitar la identificación. El modo desinstalación permanece apagado por defecto.

## Soporte y reparaciones de PC — v1.7

Abre **06 Soporte PC** en el menú de WinCare. El módulo reúne cuatro secciones. No deshabilita servicios ni borra datos durante el análisis.

**Impresoras:** comprueba el servicio Spooler, el inventario de impresoras y controladores, puertos y número de trabajos pendientes cuando Windows permite consultarlos. Abre la configuración de impresoras. La acción manual Reiniciar Spooler requiere permisos de administrador y **dos confirmaciones**. Puede interrumpir trabajos y causar reenvíos, pero no vacía los documentos de la cola ni elimina controladores.

**Errores de Windows:** eventos recientes del registro System relacionados con apagados inesperados y servicios (IDs 41, 6008, 1001, 7000, 7001, 7009, 7023, 7031 y 7034). Consulta hasta 80 eventos de los últimos 14 días. Un evento histórico no confirma un fallo actual; la ausencia de eventos no demuestra que el equipo esté libre de problemas.

**Inicio y servicios:** muestra el último arranque, estados orientativos de servicios importantes (Spooler, Windows Update, BITS, DHCP, DNS Client, EventLog y recurso compartido) y entradas de inicio mediante CIM. Permite abrir Administrador de tareas y Servicios. Un servicio detenido puede iniciarse bajo demanda; no se deshabilitan aplicaciones ni servicios automáticamente.

**Respaldos e intervenciones:** registra el problema, acciones, resultado, cliente y orden de trabajo. Guardar historial solicita confirmación y genera HTML imprimible, JSON y CSV en Reportes/soporte-AAAAMMDD-HHMMSS. Los campos escritos por el técnico se codifican de forma segura en el HTML.

**Exportar configuración:** permite seleccionar una carpeta local o USB fuera de Windows y guardar direcciones IP, DNS, gateways, impresoras y programas de inicio en CSV cuando estén disponibles. **No obtiene contraseñas Wi-Fi ni tokens**, no hace imagen de sistema y no garantiza restauración. Puede contener nombres de usuario, IP y rutas: guarda el informe de forma privada.

Las reparaciones SFC, DISM y CHKDSK ya se encuentran en **04 Taller técnico** para evitar acciones peligrosas duplicadas. Haz respaldos antes de intervenir.

## CCTV y seguridad electrónica — v1.8

Abre **07 CCTV / NVR**. No se solicitan ni almacenan usuarios, contraseñas, tokens, videos ni grabaciones. La herramienta sigue el flujo: **inventario → selección → autorización → prueba puntual → informe**.

### Inventario editable

Registra nombre, IPv4 privada, tipo declarado (Cámara IP, NVR, DVR, Switch PoE, Router u Otro), puerto (80, 443, 554, 8000, 8080 u 8899), ubicación y notas sin contraseñas. El catálogo tiene un máximo de **100 registros**. El número de equipos guardados no implica escaneos automáticos.

Se guarda en Configuracion/cctv-dispositivos.json junto al programa, si el USB permite escritura; si es de solo lectura, se utiliza Documentos/WinCarePortable/Configuracion. Se guarda un respaldo .bak al sobrescribir. No se reemplazan catálogos incompatibles o ilegibles. La categoría de cada equipo es **declarada por el técnico**, no identificada automáticamente.

### Prueba activa autorizada

1. Selecciona **un dispositivo** desde Inventario.
2. En Pruebas autorizadas, selecciona el adaptador activo y marca que tienes permiso del responsable.
3. WinCare verifica que la IP sea privada y pertenezca a la subred real del adaptador elegido.
4. Autoriza expresamente una comprobación de conectividad ICMP y una conexión TCP **a un único puerto**.
5. Examina los resultados y las recomendaciones, sin modificar ningún dispositivo.

No realiza escaneos masivos, búsqueda de credenciales, intentos de inicio de sesión, consultas RTSP/ONVIF ni acceso al video. Una respuesta ICMP no garantiza que el dispositivo funcione; un puerto abierto no demuestra que se trate de una cámara, ni verifica transmisión, grabación, compatibilidad ONVIF, RTSP ni seguridad. Los fallos podrían deberse a VLAN, PoE, alimentación, switch, cableado, firewall, servicio o IP incorrecta.

**Mapa lógico** agrupa equipos según el tipo registrado, no indica el cableado físico. El módulo **Informes** genera HTML y CSV del inventario y las pruebas: Reportes/cctv-AAAAMMDD-HHMMSS. Los datos de IP/ubicación pueden ser sensibles; revísalos antes de compartirlos.

**Pruebas automáticas:** la sintaxis, interfaz, validación de catálogo, bloqueo de IP externas, protección básica contra secretos y codificación de HTML se comprueban sin conectar con cámaras ni alterar servicios. Antes de usarse en un cliente hay que realizar pruebas funcionales en equipos y redes autorizados.

## Diagnóstico inteligente de redes — v1.6

**Cómo abrirlo:** ejecuta WinCare en Windows → selecciona **02 Red e IP** → pulsa **Abrir diagnóstico inteligente (v1.6)**. También se mantiene la auditoría anterior de procesos, conexiones TCP/UDP y firewall.

| Pestaña | Funciones |
|---|---|
| **Diagnóstico** | Adaptadores, IPv4/IPv6, prefijos, DHCP, gateway y DNS; estados Correcto, Información y Revisar, con causas probables y recomendaciones. Las consultas iniciales son **solo lectura**. |
| **Wi-Fi** | Estado de interfaces Wi-Fi, velocidad de enlace y salida informativa de Windows. La búsqueda de redes cercanas mediante netsh es **opcional** y muestra datos según idioma y controlador. |
| **Mapa LAN** | Diagrama lógico tipo árbol por adaptador, gateway y dispositivos de caché ARP, con IP, MAC observada y nombres de Red-Confiables.json si existen. No representa cableado físico. |
| **Pruebas autorizadas** | Comprobación de Internet/DNS, descubrimiento limitado LAN, Wi-Fi cercano y un puerto TCP de un dispositivo en la subred. |

### Consentimiento y límites

El programa **nunca hace ping, búsqueda Wi-Fi, consulta DNS externa ni conexión de puerto automáticamente**. Primero hay que marcar «Estoy autorizado para comprobar esta red» y aceptar la confirmación individual. La autorización empieza desmarcada en cada inicio.

- **Conectividad y DNS:** hasta dos pings al gateway privado y dos a 1.1.1.1; consulta DNS de example.com y una petición HTTPS HEAD a https://www.microsoft.com. Estos proveedores pueden observar la IP pública de salida. Un ping fallido no demuestra que Internet esté caído.
- **Descubrimiento LAN:** máximo **16 IPv4 privadas** de la subred del adaptador activo. Se muestrean unas pocas IP próximas al gateway y al PC, no toda la red. Una prueba ICMP por destino; sin escaneo de redes públicas, credenciales o ejecución de comandos remotos.
- **Comprobación de puertos:** UNA conexión TCP a una dirección IPv4 privada de la subred seleccionada y un puerto del listado (80, 443, 554, 8000, 8080, 3389, 22). No se envían contraseñas ni peticiones RTSP/ONVIF. Un puerto abierto no confirma el tipo ni la seguridad del servicio.
- **Wi-Fi cercano:** búsqueda voluntaria de SSID/BSSID, canal y señal usando netsh. No captura paquetes ni contraseñas. La existencia de varios AP en el mismo canal no constituye una medición directa de interferencia.

**IPv6:** el módulo enumera direcciones y gateways IPv6, pero las pruebas activas de descubrimiento y puertos se restringen a IPv4 privada. Una dirección APIPA 169.254.x.x motiva revisar DHCP y no se utiliza como blanco de sondeo.

### Interpretación y reportes

Los avisos muestran **posibles causas y acciones sugeridas**, no certezas. Por ejemplo: APIPA → comprobar DHCP; gateway faltante → revisar rutas; DNS fallido → revisar resolución, proxy o filtros; puerto no accesible → revisar firewall y servicio. Un equipo que no responde ping podría seguir encendido y una IP/MAC desconocida **no prueba una intrusión**.

El botón **Exportar informe** genera archivos HTML/CSV de diagnóstico, lista de dispositivos y actividad de pruebas dentro de Reportes/red-diagnostico-AAAAMMDD-HHMMSS (o Documentos si el USB es de solo lectura). El HTML no requiere Internet y codifica las cadenas externas para evitar interpretar etiquetas. Los resultados incluyen IP/MAC y pueden ser datos sensibles: compartir solo con autorización.

**Pruebas automáticas:** sintaxis PowerShell 5.1, construcción de interfaz, exclusión de IP públicas y subredes ajenas, máximo 16 IP privadas y codificación HTML, todo **sin enviar tráfico**. Antes de usarlo en redes de clientes se requieren pruebas funcionales en un entorno autorizado con hardware real.

## Seguridad de red e IP

Abre **02 Red e IP**. La auditoría existente permanece disponible e incorpora el acceso al diagnóstico inteligente v1.6. Incluye:

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
