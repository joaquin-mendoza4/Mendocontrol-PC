# Mendocontrol

Controlá tu PC con Windows desde el celular por WiFi: mouse, scroll, clics,
teclado, controles multimedia y apagado/reinicio. El servidor corre en la PC
(PowerShell, sin instalar nada) y desde el celular usás una app Android que
encuentra la PC sola, sin tener que escribir ninguna dirección IP.

---

## Qué hace

- **Mouse**: deslizás un dedo en el celular para mover el cursor; tap = clic
  izquierdo; dos dedos = scroll o clic derecho. La sensibilidad se ajusta con
  el engranaje ⚙.
- **Botones**: clic izquierdo, clic derecho y modo arrastrar.
- **Multimedia**: anterior, play/pausa, siguiente, silenciar y volumen ±.
  Funciona con Spotify, YouTube, VLC o cualquier reproductor.
- **Teclado**: el botón ⌨ abre el teclado del celular y lo que escribís se
  replica en la PC (sirve para buscar en el navegador, por ejemplo). Soporta
  tildes, ñ y emojis.
- **Energía**: apagar y reiniciar la PC (con confirmación).

---

## Componentes

| Archivo | Para qué sirve |
|---|---|
| `server.ps1` | El servidor. Sirve la interfaz web y ejecuta las órdenes del celular. |
| `index.html` | La interfaz que se ve en el celular (la sirve `server.ps1`). |
| `start.bat` | Arranca el servidor **con** ventana de consola visible (para probar/depurar). |
| `tray.ps1` | Arranca el servidor **oculto** y deja un ícono azul en la bandeja del sistema. |
| `start-tray.vbs` | Lanza `tray.ps1` sin que parpadee ninguna ventana. Es lo que usa el autoinicio. |
| `install-autostart.ps1` | Configura el inicio automático con Windows y las reglas de firewall. |
| `Mendocontrol.apk` | La app para instalar en el celular. |
| `android/` | Código fuente de la app (solo si querés recompilarla). |

---

## Requisitos

- **PC**: Windows 10 u 11. No hace falta instalar nada (usa PowerShell, que ya
  viene con Windows).
- **Celular**: Android, en la **misma red WiFi** que la PC.

---

## Puesta en marcha en una PC nueva (de cero al 100%)

### 1. Copiar la carpeta a la PC

Copiá toda la carpeta del proyecto a la PC nueva (por ejemplo a `C:\Mendocontrol`).
Puede ir en cualquier ubicación; los scripts usan rutas relativas a sí mismos.

### 2. Configurar el autoinicio y el firewall

Esto se hace **una sola vez**. Abrí PowerShell **como administrador**
(clic derecho en el menú Inicio → "Terminal (Administrador)" o
"Windows PowerShell (Administrador)"), navegá a la carpeta y ejecutá:

```powershell
cd C:\Mendocontrol
powershell -ExecutionPolicy Bypass -File install-autostart.ps1
```

Esto hace dos cosas:

- Crea un acceso directo en tu carpeta de Inicio, así Mendocontrol arranca
  **oculto** (solo el ícono de la bandeja) cada vez que prendés la PC.
- Crea las reglas de firewall para que el celular pueda conectarse
  (TCP 8765 para la app + UDP 8766 para que la app encuentre la PC sola).

> **Por qué como administrador**: las reglas de firewall las necesita. Si lo
> corrés sin permisos de administrador, el autoinicio igual se instala, pero
> te va a avisar que no pudo crear las reglas de firewall, y entonces el
> celular probablemente no logre conectarse.

### 3. Verificar que la red WiFi sea "privada"

El firewall solo permite la conexión en redes marcadas como **privadas**.
En Windows: **Configuración → Red e Internet → WiFi → (tu red) → Tipo de
perfil de red → Privada**. (Las redes de casa normalmente ya lo están; las
públicas, no.)

### 4. Arrancar ahora sin reiniciar

El autoinicio se activa solo en el próximo arranque de Windows. Para usarlo
ya mismo sin reiniciar, hacé **doble clic en `start-tray.vbs`**.

Vas a ver aparecer el **ícono azul** en la bandeja del sistema (abajo a la
derecha, puede estar dentro del menú de íconos ocultos ⌃) y un globo que
muestra la dirección para el celular.

### 5. Instalar la app en el celular

1. Pasá el archivo `Mendocontrol.apk` al celular (por WhatsApp a vos mismo,
   cable USB, Google Drive, etc.).
2. Abrilo en el celular e instalalo. Android te va a pedir permitir
   **"instalar apps de orígenes desconocidos"** la primera vez: aceptá.

### 6. Usarla

1. Asegurate de que el celular esté en la **misma red WiFi** que la PC.
2. Abrí la app **Mendocontrol** en el celular.
3. Encuentra la PC sola y carga la interfaz. **Listo.**

A partir de acá, cada vez que prendas la PC, el servidor arranca solo y oculto;
solo tenés que abrir la app en el celular.

---

## Uso diario

- **PC**: nada que hacer. Arranca solo al prender la PC.
- **Celular**: abrí la app Mendocontrol.
- **Ver si está corriendo / la IP**: pasá el mouse o hacé clic derecho sobre el
  ícono azul de la bandeja. El menú tiene opciones para ver la dirección,
  probarla en el navegador de la PC, o **Salir** (que cierra el servidor).

---

## Solución de problemas

**La app dice "No se encontró la PC".**
- Confirmá que ambos estén en la misma red WiFi.
- Confirmá que el ícono azul esté en la bandeja de la PC (si no, doble clic en
  `start-tray.vbs`).
- Revisá que la red WiFi esté marcada como **privada** (paso 3).
- Si instalaste el autoinicio sin ser administrador, las reglas de firewall no
  se crearon: volvé a correr `install-autostart.ps1` como administrador.

**Escribo con el teclado pero no aparece nada en la PC.**
- La ventana enfocada en la PC tiene que aceptar texto (un campo, el navegador,
  etc.).
- Si la app enfocada corre **como administrador** y el servidor no, Windows
  bloquea las teclas (es una protección del sistema, no un error). Solución:
  corré `tray.ps1` / `start-tray.vbs` también como administrador.

**Quiero ver qué está pasando (consola).**
- Cerrá el servidor desde el ícono de la bandeja (Salir) y arrancá con
  `start.bat`, que muestra la consola con los mensajes de conexión.

**Desinstalar el autoinicio.**
```powershell
powershell -ExecutionPolicy Bypass -File install-autostart.ps1 -Remove
```

---

## Cómo funciona (resumen técnico)

- `server.ps1` levanta un servidor TCP en el puerto **8765**. Sirve `index.html`
  por HTTP y abre un **WebSocket** en `/ws` por donde el celular manda las
  órdenes (mover mouse, teclas, multimedia, etc.).
- Las órdenes se ejecutan llamando a `user32.dll` de Windows (`SetCursorPos`,
  `mouse_event`, `SendInput`/`keybd_event`).
- En paralelo, escucha **broadcasts UDP** en el puerto **8766**: cuando la app
  Android pregunta `MENDOCONTROL?`, el servidor responde `MENDOCONTROL:8765`.
  Así la app obtiene la IP de la PC del propio paquete de respuesta, sin que el
  usuario escriba nada.
- La app Android (`android/`) es un WebView que hace ese descubrimiento y carga
  la interfaz web. Como es solo un envoltorio, cualquier cambio futuro en
  `index.html` aparece en la app sin recompilarla.

### Recompilar la APK (opcional)

Solo si modificás el código de `android/`. Necesitás el SDK de Android y un JDK
(los trae Android Studio). Desde la carpeta `android/`:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
gradle assembleDebug
```

El APK queda en `android/app/build/outputs/apk/debug/app-debug.apk`. Copialo a
la raíz como `Mendocontrol.apk`.

> Nota: `android/local.properties` apunta al SDK de **esta** máquina y no se
> versiona. En otra PC, crealo con la línea `sdk.dir=<ruta-al-SDK>`.
