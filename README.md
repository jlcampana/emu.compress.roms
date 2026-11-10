# emu.compress.roms

Script para comprimir y descomprimir ROMs e ISOs de emuladores, inspirado en
la herramienta de compresión de EmuDeck pero trabajando sobre el directorio
actual en lugar de rutas fijas.

## Formatos

| Formato | Uso | Herramienta |
|---------|-----|-------------|
| CHD | CD (cue/gdi/toc/iso) y DVD (iso) | `chdman` |
| RVZ | GameCube / Wii (iso, gcm, wbfs) | `dolphin-tool` |
| CSO | PSP (iso) | `maxcso` o `ciso` |
| 3DS recortado | Nintendo 3DS (3ds, cci) | `3dstool` |
| XISO | Xbox (iso) | `extract-xiso` |
| 7z | ROMs de sistemas RetroArch | `7z` |

Extensiones que se meten en 7z: `nes`, `fds`, `sfc`, `smc`, `gb`, `gbc`,
`gba`, `md`, `gen`, `smd`, `gg`, `n64`, `z64`, `v64`, `ws`, `wsc`, `pce`,
`sgx`, etc. Las ROMs sueltas `.bin`, `.rom` y `.dsk` de sistemas de cartucho
también se comprimen, pero nunca los archivos de `bios/` ni las pistas de un
`.cue`/`.gdi`.

## Uso

```bash
emu-compress [opciones] [compress|decompress|list] [ruta]
```

Ejemplos:

```bash
# Comprime todo lo que haya en el directorio actual (y subdirectorios)
emu-compress compress

# Comprime una carpeta concreta y borra los originales tras convertir
emu-compress compress ~/roms/PS1 --delete

# Descomprime CHD/CSO/RVZ/7z
emu-compress decompress ~/roms/PSP

# Solo muestra qué haría
emu-compress list ~/roms/MegaCD
```

Opciones útiles:

- `-n, --dry-run`: no modifica nada.
- `-d, --delete`: borra los originales tras una conversión correcta.
- `-k, --keep`: conserva los originales (por defecto).
- `-f, --force`: sobrescribe salidas existentes.
- `--no-recursive`: no entra en subdirectorios.
- `--system SISTEMA`: fuerza el sistema (por ejemplo `ps2`, `psx`, `psp`).
- `--psp-format cso|chd`: formato para ISOs de PSP.
- `--cd-format cue|gdi`: formato al extraer un CHD de CD.
- `--verify`: verifica CHD y 7z después de crearlos; en RVZ compara el CRC32 del
  disco de entrada y de salida (lee ambos completos, es más lento).
- `--log ARCHIVO`: guarda la salida en un archivo.

## Detección del sistema

Si el directorio actual se llama como un sistema (`PS1`, `PS2`, `PSP`, `GC`,
`Wii`, `Xbox`, `Saturn`, `MegaCD`, `PCE`, `Dreamcast`, etc.), **se asume ese
sistema para todos los archivos, incluidos los subdirectorios**. Por ejemplo,
ejecutar el script dentro de `~/roms/PS2` tratará como DVD de PS2 todos los
`.iso` que encuentre, aunque estén en carpetas como `Disc 1/` o `Disc 2/`.

También reconoce variantes habituales de carpeta:

- `dreamcast.gdemu` → `dreamcast`
- `msx.all`, `msx.original` → `msx`
- `pcenginecd.check` → `pcenginecd`
- `pcengine.check` → `pcengine`
- `3ds-nds` → `n3ds`
- `PS1`/`PlayStation` → `psx`, `PlayStation 2` → `ps2`, `Sega Saturn` →
  `saturn`, `Mega CD`/`Sega CD` → `megacd`, etc.

Las pistas de un `.cue`/`.gdi`/`.toc` (por ejemplo `track01.iso` dentro de
`dreamcast.gdemu`) no se comprimen por separado: se convierten junto con su
descriptor. Los `.iso` de `xbox360` se omiten a propósito, igual que los
archivos de `bios/` y `bios-lakka/`.

Si el nombre del directorio no es un sistema conocido, se mira el contenido
real de los `.iso` (GameCube, Wii, Xbox, PSP, PS2), después los nombres de las
carpetas intermedias, luego las carpetas padre (por ejemplo, si se ejecuta en
`MegaCD/oth/USA` se detecta `MegaCD`) y, como último recurso, el tamaño
(>= 700 MiB se trata como DVD y el resto como CD).

Para forzar el sistema cuando la carpeta no se llama como tal:

```bash
emu-compress compress ~/roms/PS2 --system ps2
```

## Dependencias

En Fedora:

```bash
sudo dnf install mame-tools 7zip
```

En Ubuntu/Debian:

```bash
sudo apt install mame-tools p7zip-full
```

Además hacen falta, según los formatos que se vayan a usar:

- `dolphin-tool` (paquete Dolphin o Flatpak `org.DolphinEmu.dolphin-emu`). Con
  Flatpak, el script concede acceso a la carpeta de cada juego con
  `--filesystem`, así que funciona también fuera de `/home` y `/run/media`.
- `maxcso` o `ciso` para CSO.
- `3dstool` para recortar 3DS.
- `extract-xiso` para XISO.

Si están instaladas, el script también reutiliza las herramientas que incluye
EmuDeck en `~/.config/EmuDeck/backend/tools/chdconv/`.

## Seguridad

Por defecto **no se borra ningún original**. Para borrarlos hay que usar
`--delete`, y en ese caso el script solo elimina el original después de
comprobar que la salida se ha creado correctamente.

Excepciones a tener en cuenta:

- Recortar un `.3ds`/`.cci` es una operación en sitio: el archivo se renombra
  a `(Trimmed)` y se elimina el relleno sobrante, aunque no uses `--delete`.
  No se pierden datos, solo el padding.
- Los archivos de `bios/` y `bios-lakka/` nunca se tocan.
- Las pistas de un `.cue`/`.gdi`/`.toc` solo se borran con `--delete` y solo
  si están en la misma carpeta que el descriptor.
- Los `.iso` de `xbox360` se omiten para no confundirlos con Xbox clásico.
