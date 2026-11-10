# Contexto del proyecto — emu.compress.roms

Documento de traspaso para que otra sesión de Claude pueda continuar el trabajo
sin releer toda la conversación. Última actualización: 2026-11-10 (RVZ probado).

## 1. Objetivo

Crear un script equivalente al **Bulk Compression / Bulk Decompression de
EmuDeck**, pero que:

- Trabaje sobre el **directorio actual** (o una ruta indicada), no sobre rutas
  fijas de EmuDeck.
- Recorra **subdirectorios** y asuma que todo lo que hay debajo pertenece al
  mismo sistema que el directorio actual.
- Se pueda instalar con `curl ... | bash`.
- Detecte **Fedora vs Ubuntu/Debian** e instale las dependencias necesarias.
- Comprima/descomprima: CHD (CD/DVD), CSO (PSP), RVZ (GC/Wii), 3DS recortado,
  XISO (Xbox) y 7z (sistemas RetroArch).
- Conserve los originales por defecto; borrarlos solo con `--delete`.
- Maneje correctamente nombres con espacios, comillas y saltos de línea
  (EmuDeck tiene un bug conocido ahí).

Documento original de requisitos: `PROYECTO.md`.
Referencia visual de formatos: `image.png`.

## 2. Estado actual

### Hecho y probado

- Script principal: `/home/pandi/Projects/emu.compress.roms/emu-compress`
  (Bash, ~1267 líneas, versión `0.1.0`, ejecutable).
- Compresión/descompresión de:
  - CHD CD (`cue`/`gdi`/`toc`) con `chdman createcd` / `extractcd`.
  - CHD DVD (`iso`) con `chdman createdvd` / `extractdvd`.
  - CSO de PSP con `ciso` (o `maxcso` si existe).
  - RVZ de GameCube/Wii con `dolphin-tool` (incluye `.gcm` y `.wbfs`).
  - 3DS recortado con `3dstool -r` (incluye `.3ds` y `.cci`).
  - XISO de Xbox con `extract-xiso`.
  - 7z de ROMs RetroArch.
- Recursividad activada por defecto (`--no-recursive` para desactivarla).
- Detección de sistema por nombre de directorio, subcarpetas, carpetas padre,
  contenido de los `.iso` y tamaño.
- `--system SISTEMA` para forzar el sistema.
- Opciones: `--delete`, `--keep`, `--force`, `--verify`, `--log`,
  `--psp-format`, `--cd-format`, `--chd-dvd-codec`, `--chd-cd-codec`,
  `--7z-level`, `--dry-run`, `--yes`, `--quiet`, `--verbose`.
- `list` es un dry-run de compresión y no modifica nada.
- README actualizado con uso, formatos, detección, dependencias y seguridad.

### Pendiente

1. **Instalador `curl ... | bash`** con detección Fedora/Ubuntu. No iniciado.
   No hay URL de repositorio todavía; habrá que decidir dónde publicarlo.
2. ~~Probar RVZ real~~ — hecho (ver §10).
3. Decidir si se soportan `.nds`/`.cia` (ahora se omiten; EmuDeck tampoco los
   soporta) y `.cdi` de Dreamcast (ahora se omite).
4. Valorar si se añaden `.d88`/`.hdf`/`.xdf` de X68000 (ahora se omiten).
5. Hacer commit cuando el usuario lo pida. Ahora mismo todo está sin commitear.

## 3. Archivos del repositorio

```
/home/pandi/Projects/emu.compress.roms/
├── emu-compress      # script principal (untracked, ejecutable)
├── README.md         # documentación (modificado, antes era solo el título)
├── PROYECTO.md       # requisitos originales (untracked)
├── image.png         # referencia de formatos de EmuDeck (untracked)
└── CLAUDE.md         # este documento
```

Estado Git:

```
 M README.md
?? PROYECTO.md
?? emu-compress
?? image.png
?? CLAUDE.md
```

No se ha hecho ningún commit.

## 4. Rutas reales importantes

- ROMs reales: `/run/media/pandi/Roms/202611` (~869 GB).
- Otro árbol real: `/run/media/pandi/Roms/sistemas` (una carpeta por sistema;
  a veces hay carpetas dentro de carpetas). El disco está al 98 % (~122 GB
  libres).
- Árbol secundario de pruebas: `/home/pandi/roms`.
- Herramientas incluidas por EmuDeck:
  `~/.config/EmuDeck/backend/tools/chdconv/`
  (`chdman5`, `ciso`, `3dstool`, `extract-xiso`, `chddeck.sh`).
- Script de referencia de EmuDeck:
  `~/.config/EmuDeck/backend/tools/chdconv/chddeck.sh`.

## 5. Uso

```bash
emu-compress [opciones] [compress|decompress|list] [ruta]
```

Ejemplos:

```bash
# Ver qué haría en el directorio actual y subdirectorios
/home/pandi/Projects/emu.compress.roms/emu-compress list

# Comprimir todo el directorio actual
/home/pandi/Projects/emu.compress.roms/emu-compress compress

# Comprimir borrando originales tras verificar la salida
/home/pandi/Projects/emu.compress.roms/emu-compress compress --delete

# Descomprimir CHD/CSO/RVZ/7z
/home/pandi/Projects/emu.compress.roms/emu-compress decompress

# Forzar sistema si la carpeta no se llama como tal
/home/pandi/Projects/emu.compress.roms/emu-compress compress --system ps2

# Solo el directorio indicado, sin entrar en subcarpetas
/home/pandi/Projects/emu.compress.roms/emu-compress compress --no-recursive
```

## 6. Detección de sistema

Prioridad en `system_hint()`:

1. `--system` si se pasa.
2. **Nombre del directorio actual** (`ROOT`). Si es un sistema conocido, se
   aplica a todos los archivos, incluidos los subdirectorios.
3. Nombres de las carpetas intermedias dentro de `ROOT`.
4. Nombres de las carpetas padre (hasta 3 niveles). Ejemplo: ejecutar en
   `MegaCD/oth/USA` detecta `MegaCD`.
5. Contenido real de los `.iso` (`iso_kind()`): Xbox, GameCube, Wii, PSP, PS2.
6. Tamaño: `>= 700 MiB` se trata como DVD; el resto como CD.

`normalize_system()`:

- Pasa a minúsculas.
- Elimina espacios, `_` y `-`.
- Se queda con la parte anterior al primer punto (para variantes).
- Alias principales:
  - `PS1`, `PlayStation`, `PlayStation 1` → `psx`
  - `PlayStation 2` → `ps2`
  - `PlayStation Portable` → `psp`
  - `GameCube`, `NGC` → `gc`
  - `Nintendo Wii` → `wii`
  - `Xbox` → `xbox`; `Xbox 360` → `xbox360`
  - `3DS`, `Nintendo 3DS`, `3ds-nds` → `n3ds`
  - `Sega Saturn` → `saturn`
  - `Dreamcast`, `DC` → `dreamcast`
  - `Mega CD`, `Sega CD` → `megacd`
  - `PC Engine`, `PCE`, `TurboGrafx-16` → `tg16`
  - `TurboGrafx-CD` → `tg-cd`
  - `dreamcast.gdemu` → `dreamcast`
  - `msx.all`, `msx.original` → `msx`
  - `pcenginecd.check` → `pcenginecd`
  - `pcengine.check` → `pcengine`

Listas relevantes:

- `is_cd_system()`: 3do, amiga, amigacd32, atomiswave, cdimono1, cdtv,
  dreamcast, megacd, naomi, neogeocd, pcenginecd, pcfx, psx, saturn, segacd,
  tg-cd, etc.
- `is_cart_system()`: a26, a78, gb, gbc, gba, gg, genesis, md, megadrive,
  msx, n64, nes, ngp, ngc, pc2, pce, pcengine, sega32x, sfc, sgx, snes, tg16,
  ws, wsc, wonderswan, wonderswancolor, z64, etc.
- `is_7z_ext()`: ngp, ngc, a26, lnx, ws, pc2, wsc, n64, ndd, v64, z64, gb,
  dmg, gba, gbc, nes, fds, unf, unif, bs, fig, sfc, smc, swx, 32x, gg, gen,
  md, smd, pce, sgx.

## 7. Reglas especiales de clasificación

- `.cue`, `.gdi`, `.toc` → CHD CD.
- `.iso`:
  - Si hay un `.cue`/`.gdi`/`.toc` hermano con el mismo nombre base → se
    omite el `.iso` (manda el descriptor).
  - Si el sistema es `psp` → CSO (o CHD si `--psp-format chd`).
  - Si es `gc`/`wii`/`primehacks` → RVZ.
  - Si es `xbox` → XISO.
  - Si es `xbox360` → **se omite**.
  - Si es `ps2` → CHD DVD.
  - Si es un sistema CD → CHD CD.
  - Sin pista y `>= 7 GiB` → se omite (casi seguro Xbox 360).
  - Si no, se mira el contenido (`iso_kind`) y luego el tamaño.
- `.gcm`, `.wbfs` → RVZ.
- `.3ds`, `.cci` → recorte 3DS. El archivo se renombra a `(Trimmed)`.
- `.bin`, `.rom`, `.dsk`:
  - Solo se pasan a 7z si el sistema es de cartucho.
  - `.bin` exige tamaño `>= 64 KiB`; `.rom`/`.dsk`, `>= 16 KiB`.
  - Las pistas de un `.cue`/`.gdi`/`.toc` se omiten siempre.
- Cualquier archivo dentro de `bios/`, `bios-lakka/` o `bios_lakka/` se omite.
- Las pistas referenciadas por un `.cue`/`.gdi`/`.toc` de la misma carpeta se
  omiten (`is_track_file`). Esto es clave en `dreamcast.gdemu`, donde hay
  `track01.iso`, `track02.raw`, etc.
- Los `.iso` de `xbox360` se omiten para no confundirlos con Xbox clásico.

## 8. Seguridad

- Por defecto **no se borra ningún original**.
- `--delete` solo borra después de comprobar que la salida existe y no está
  vacía.
- Para CHD de CD con `cue`/`gdi`, solo se borran las pistas que están
  directamente en la misma carpeta que el descriptor; nunca rutas externas.
- Si `extract-xiso` falla, se restaura el `.old`.
- Excepción: recortar `.3ds`/`.cci` es una operación en sitio. El archivo se
  renombra a `(Trimmed)` y se elimina el padding, aunque no se use `--delete`.
  No se pierden datos, solo relleno.
- Nunca se toca `bios/` ni `bios-lakka/`.

## 9. Dependencias y herramientas detectadas

En el sistema actual (Fedora):

- `chdman` → `/usr/bin/chdman` (mame-tools 0.289-1.fc44).
- `7z` → `/usr/bin/7z` (7zip 26.04-1.fc44).
- `ciso`, `3dstool`, `extract-xiso`, `chdman5` → EmuDeck
  `~/.config/EmuDeck/backend/tools/chdconv/`.
- Dolphin → Flatpak `org.DolphinEmu.dolphin-emu` (stable 2609a).
  El script usa `flatpak run --command=dolphin-tool org.DolphinEmu.dolphin-emu`.
- No hay `maxcso`; se usa `ciso`.

Detección en el script:

- `tool_path()` busca primero en `PATH` y luego en `$EMUDECK_TOOLS`.
- `require_dolphin()` comprueba que `DOLPHIN_TOOL` no esté vacío.
- `run_dolphin`/`dolphin_cmd` construyen la llamada; si es Flatpak
  (`DOLPHIN_FLATPAK`), añaden `--filesystem` por cada carpeta usada.
- `verify_output()` verifica CHD con `chdman verify` y 7z con `7z t`.

## 10. Pruebas realizadas

### Pruebas reales

- CHD real de Saturn (`Galaxy Deka Gayvan.chd`):
  - Descomprimido y recompuesto.
  - `chdman verify` correcto.
- GDI real de Dreamcast (`dreamcast.gdemu/01/02`):
  - Compresión a CHD: 118 MiB → 78 MiB.
  - `chdman verify` correcto.
  - Descompresión a GDI y recompresión: verificación correcta.
- CCI real `Mario Party - The Top 100 (USA).cci`:
  - Recorte con `3dstool` correcto (ya estaba recortado, 0 % de ahorro).
- Cue/bin multi-pista:
  - Compresión, borrado con `--delete` y verificación correctos.
- Nombres con espacios, comillas simples y saltos de línea: correctos.
- `--system`, `--no-recursive`, `--force`, `--log`, `--verify`: correctos.

- RVZ real (2026-11-10), copias en el scratchpad:
  - GC `Wario World (Europe)`: RVZ → ISO → RVZ → ISO, MD5 de ISO idéntico;
    el RVZ regenerado mide exactamente lo mismo que el original.
  - Wii `.wbfs` japonés en subcarpeta anidada (`Japan/Raros/`): 290 MiB → 48 MiB,
    CRC32 correcto, `--delete` borró el `.wbfs` solo tras verificar.
  - Bug encontrado y corregido: Dolphin Flatpak no veía archivos en `/tmp`
    (`filesystem=host` no incluye `/tmp`). Ahora `dolphin_cmd()` añade
    `--filesystem=<dir>` de la entrada y la salida a cada `flatpak run`.
  - `--verify` en RVZ (compresión y descompresión): `verify_rvz_pair()`
    compara `dolphin-tool verify -a crc32` de entrada y salida.
  - Dry-run en `/run/media/pandi/Roms/sistemas`: `gc` 35 conversiones,
    `wii` 11 (ISO y WBFS), 0 errores.

### Barrido real completo

Comando:

```bash
/home/pandi/Projects/emu.compress.roms/emu-compress list /run/media/pandi/Roms/202611
```

Resultado:

```
Resumen: 3868 se convertirían, 42644 omitidos, 0 errores (de 46512 archivos)
```

Acciones:

| Acción | Cantidad |
|--------|----------|
| 7z | 3638 |
| CHD (CD+DVD) | 144 |
| CSO | 39 |
| RVZ | 46 |
| 3DS trim | 1 |

Por carpeta (solo conversiones):

```
2229 msx.original
 325 famicomdisk.check
 287 msx.all
 203 wonderswancolor
 184 nes
  89 snes.check
  84 ps2
  77 megadrive
  56 dreamcast.gdemu
  53 pcengine.check
  49 snes
  47 pcengine
  39 psp
  35 gc
  31 gb
  29 gba
  15 gbc
  14 neogeo.pocket
  11 wii
   3 saturn
   3 gg
   3 famicomdisk
   1 ps1
   1 3ds-nds
```

7z por extensión:

```
2502 dsk
 328 fds
 184 nes
 112 ws
 103 sfc
  96 pce
  91 wsc
  73 md
  35 smc
  30 gb
  29 gba
  16 gbc
  14 rom
  13 ngc
   4 sgx
   4 bin
   3 gg
   1 ngp
```

Notas del barrido:

- El árbol real tiene carpetas que no estaban en la lista inicial del usuario:
  `famicomdisk.check`, `snes.check`, `gb`, `gba`, `gbc`, `gg`,
  `neogeo.pocket`, etc. El script las detecta por extensión.
- Los `.iso` de `xbox360` se omitieron correctamente.
- Las pistas de `dreamcast.gdemu` se omitieron; solo se convierten los `.gdi`.
- Los `.bin` convertidos son 4 ROMs de Mega Drive; no se tocaron pistas de CD
  ni BIOS.

### Barrido de `/home/pandi/roms`

```
Resumen: 46 se convertirían, 90 omitidos, 0 errores (de 136 archivos)
```

Incluye 21 CHD y 25 7z (`.pce`, `.sfc`, `.md`, `.gba`, `.gb`, etc.).

## 11. Decisiones y notas técnicas

- El script es Bash puro; usa `find`, `mapfile`, `sed`, `awk`, `od`, `dd`.
- `normalize_system`, `lower_ext` e `is_excluded_path` usan expansión de
  parámetros de Bash (`${var,,}`, `${var//...}`) para evitar subprocesos.
  Esto redujo el escaneo de `msx.all` de ~2 min a ~44 s.
- **No editar `emu-compress` mientras hay una ejecución larga en curso.**
  Bash lee el script de forma incremental; ya provocó un error de sintaxis una
  vez. Si hay que cambiar algo, esperar a que termine el proceso.
- `list` no modifica nada y es la forma recomendada de validar antes de
  comprimir.
- `decompress` de 7z extrae al directorio y no intenta reconstruir el nombre
  original; el `.7z` se conserva salvo `--delete`.
- `decompress` de CHD CD genera `.cue` por defecto; con `--cd-format gdi`
  genera `.gdi`.
- `--psp-format chd` permite CHD en vez de CSO para PSP.
- El script reutiliza herramientas de EmuDeck si están instaladas.

## 12. Próximos pasos recomendados

1. **Instalador**:
   - Crear `install.sh` que detecte Fedora/Ubuntu con `/etc/os-release`.
   - Fedora: `sudo dnf install mame-tools 7zip`.
   - Ubuntu/Debian: `sudo apt install mame-tools p7zip-full`.
   - Descargar `emu-compress` desde la URL del repositorio y copiarlo a
     `~/.local/bin/` (o `/usr/local/bin/`).
   - Hacerlo compatible con `curl ... | bash`.
   - Decidir URL definitiva del repositorio.
2. **Probar RVZ real**:
   - Copiar una ISO pequeña de GC/Wii a `/tmp` y ejecutar
     `emu-compress compress` con `--verify`.
   - Comprobar que Dolphin Flatpak se invoca bien.
3. **Decidir formatos pendientes**:
   - `.nds`/`.cia`: EmuDeck no los soporta; probablemente dejarlos omitidos.
   - `.cdi` de Dreamcast: EmuDeck no lo convierte; probablemente omitido.
   - `.d88`/`.hdf`/`.xdf` de X68000: valorar si añadirlos a 7z.
4. **Documentación**:
   - Actualizar README/help si se añade algo nuevo.
   - Mantener este `CLAUDE.md` al día.
5. **Commit** cuando el usuario lo pida.

## 13. Comandos útiles

```bash
# Estado del repo
cd /home/pandi/Projects/emu.compress.roms
git status --short

# Comprobar sintaxis
bash -n emu-compress

# Ver versión y ayuda
./emu-compress --version
./emu-compress --help

# Dry-run de una carpeta real
./emu-compress list /run/media/pandi/Roms/202611/ps2

# Comprimir una carpeta con verificación
./emu-compress compress /run/media/pandi/Roms/202611/ps2 --verify

# Descomprimir una carpeta
./emu-compress decompress /run/media/pandi/Roms/202611/psp

# Ver herramientas
command -v chdman 7z dolphin-tool maxcso ciso 3dstool extract-xiso
flatpak list --columns=application | grep -i dolphin
```

## 14. Advertencias

- No ejecutar `compress` sobre todo `/run/media/pandi/Roms/202611` sin haber
  hecho antes `list` y sin espacio libre suficiente: son 3868 conversiones,
  muchas de ellas de MSX (`dsk`) y FDS.
- El recorte 3DS modifica el archivo en sitio (renombra a `(Trimmed)`).
- Los `.iso` de `xbox360` se omiten a propósito.
- Los archivos de `bios/` y `bios-lakka/` nunca se tocan.
- Si se interrumpe una conversión, la salida parcial puede quedar en disco;
  usar `--force` para rehacerla.
