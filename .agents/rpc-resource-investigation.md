# Bitácora: crecimiento de memoria con RPC UDP y velocidad de emulación

Fecha de inicio: 2026-08-27

Alcance: investigación solamente. No cambiar la lógica del emulador. Este archivo conserva
hallazgos verificables y el estado de la investigación para poder retomarla.

## Contrato de investigación

Determinar primero qué rutas cambian con la velocidad y clasificar el crecimiento como fuga
real, cola/buffer ilimitado, limpieza diferida, high-water mark del allocator, caché u otra
retención. Reportar reproducción, patrón de crecimiento, ruta de asignación/retención, evidencia,
procedencia upstream o LimoMada3DS, corrección mínima y verificación.

## Checkpoint 1 — cola RPC ilimitada amplificada 32 veces

El UDP relevante para este fork es el servidor de scripting/RPC en el puerto 45987
(`src/core/rpc`), no el cliente Cemuhook de entrada en el puerto 26760. El commit `b003e78d4`
aumentó `MAX_PACKET_DATA_SIZE` de 32 a 1024 bytes para permitir lecturas de memoria más grandes.

El receptor crea un `Packet` por cada datagrama válido y lo empuja a
`RPCServer::request_queue`. Esa cola es `Common::SPSCQueue`, una lista enlazada dinámica sin
límite, rechazo, coalescing ni backpressure. Hay un único hilo consumidor. Cada `Packet`
contiene siempre `std::array<u8, 1024>`, incluso cuando una petición de lectura solo contiene
los 8 bytes de dirección y tamaño. Por tanto, cualquier diferencia sostenida entre tasa de
entrada y procesamiento acumula aproximadamente un KiB más metadatos/asignaciones por petición;
el cambio del fork multiplicó por 32 el componente dominante del backlog.

Hipótesis principal actual: no es necesario que exista una fuga de propiedad. Es crecimiento
no acotado de trabajo pendiente. Al subir la velocidad, el productor externo o el patrón de
sondeo puede superar con mayor facilidad al único consumidor; además cada respuesta hace una
lectura de memoria y un `send_to` síncrono antes de consumir la siguiente solicitud.

Evidencia clave:

- `src/core/rpc/packet.h`: `Packet::packet_data` es un arreglo fijo de
  `MAX_PACKET_DATA_SIZE == 1024`.
- `src/core/rpc/udp_server.cpp`: `HandleReceive` acepta, reserva y encola, y rearma de inmediato
  otra recepción; no consulta la profundidad de la cola.
- `src/core/rpc/rpc_server.h/.cpp`: una `SPSCQueue<std::unique_ptr<Packet>>`, un solo consumidor y
  `QueueRequest` siempre hace `Push`.
- `src/common/threadsafe_queue.h`: cada `Push` asigna un nodo con `new`; no existe capacidad
  máxima.

Pendiente para el siguiente checkpoint: medir o modelar la tasa de crecimiento, revisar el
camino de logging y el envío síncrono, estudiar si el aumento de velocidad tiene otra cola o
caché no acotada, y contrastar contra el código anterior/upstream.

## Checkpoint 2 — reproducción aislada confirma retención lineal y liberación correcta

Se añadió una sonda fuera de la lógica del emulador en
`.agents/experiments/rpc_queue_probe.cpp`. Usa las clases reales `Packet` y `SPSCQueue`, encola
100 000 peticiones RPC y luego las vacía. Se compiló con el MinGW de CLion y se ejecutó con sus
DLL en `PATH`.

Resultados:

```text
sizeof(Packet)=1072, MAX_PACKET_DATA_SIZE=1024
cola 0:       private 0.97 MiB,  working set 4.93 MiB
cola 10 000:  private 12.29 MiB, working set 16.03 MiB
cola 50 000:  private 56.65 MiB, working set 59.48 MiB
cola 100 000: private 111.84 MiB, working set 113.60 MiB
cola vacía:   private 1.88 MiB,  working set 5.70 MiB
dos segundos después: private 1.88 MiB, working set 5.71 MiB
```

La pendiente observada es aproximadamente 1.11 KiB de memoria privada por solicitud pendiente,
coherente con un `Packet` de 1072 bytes más el nodo enlazado y overhead del allocator. La memoria
se recupera al consumir la cola. Clasificación respaldada por el experimento: **buffer/cola no
acotada**, no fuga de ownership y no high-water mark significativo del allocator de MinGW en este
caso.

El primer intento de ejecutar la sonda sin añadir el runtime MinGW a `PATH` mostró tres diálogos
por DLL faltantes (`libgcc_s_seh-1.dll`, `libwinpthread-1.dll`, `libstdc++-6.dll`). El segundo
intento, con el `PATH` correcto, fue exitoso; esos diálogos no proceden del emulador.

Procedencia: el diseño de cola ilimitada y un consumidor único es upstream (Citra/Lime3DS,
presente desde el RPC original). La magnitud de 1072 bytes por pendiente se debe principalmente
al aumento LimoMada3DS de 32 a 1024 bytes; la modificación amplifica un defecto upstream, pero no
lo origina.

## Checkpoint 3 — fuga real upstream en el decoder AAC

La ruta HLE de audio por defecto contiene una fuga conocida y posteriormente corregida por
Azahar. En `src/audio_core/hle/aac_decoder.cpp`, `AACDecoder::Decode` llama
`NeAACDecInit(decoder, ...)` para **cada solicitud de decodificación** (línea 107), no una vez por
stream. El ajuste de velocidad permite procesar más audio emulado por segundo real y, por tanto,
multiplica directamente la tasa de fuga. Esto es independiente del RPC UDP y de las modificaciones
de LimoMada3DS.

La causa puede seguirse hasta FAAD2 dentro del propio repositorio:

- `externals/faad2/faad2/libfaad/decoder.c`: cada `NeAACDecInit` reemplaza `hDecoder->fb` con un
  nuevo `filter_bank_init` sin liberar el anterior.
- `externals/faad2/faad2/libfaad/filtbank.c`: `filter_bank_init` reserva `fb_info` y dos planes MDCT.
- `NeAACDecClose` solo libera el último `hDecoder->fb`; todas las instancias sobrescritas quedan
  perdidas.

Se creó `.agents/experiments/aac_init_leak_probe.cpp`, enlazado contra el `libfaad2.a` exacto del
build. Repite `NeAACDecInit` sobre un solo decoder con un encabezado ADTS válido:

```text
0 init:       private 0.98 MiB, working set 4.87 MiB
500 init:     private 5.86 MiB, working set 9.79 MiB
2 500 init:   private 24.59 MiB, working set 28.10 MiB
5 000 init:   private 48.09 MiB, working set 51.00 MiB
tras NeAACDecClose: private 48.09 MiB, working set 51.00 MiB
```

La pendiente es aproximadamente 9.65 KiB por inicialización y la memoria no se recupera al cerrar
el decoder: esta sí es una fuga real de ownership. A 44.1–48 kHz y 1024 muestras por frame, una
sola inicialización por frame implica aproximadamente 43–47 llamadas por segundo emulado: del
orden de 0.4–0.45 MiB/s a 100%, 0.8–0.9 MiB/s a 200% y 2–2.25 MiB/s a 500%, antes de considerar
variaciones del juego y overhead.

Prueba de control: la misma sonda se ejecutó 5000 veces cerrando el handle anterior antes de abrir
e inicializar otro. La memoria privada pasó de 0.98 a solo 1.08 MiB y se estabilizó desde la
iteración 2500; el working set se estabilizó en 5.10 MiB. Esto confirma que FAAD2 libera
correctamente cuando se respeta el ciclo de vida, y que el problema es sobrescribir internamente
el filter bank mediante inicializaciones repetidas.

Confirmación upstream: Azahar PR #1167, fusionado el 2025-06-21, documenta que Pokémon X/Y sufrían
esta fuga porque `NeAACDecInit` se ejecutaba en cada frame. La corrección inicializa una sola vez
por stream y reinicializa al recibir `DecoderCommand::Init`; también contempla cargar savestates.
Fuente: https://github.com/azahar-emu/azahar/pull/1167

Procedencia: **100% upstream**. El archivo local no tiene cambios de LimoMada3DS y conserva el
código de Lime3DS/Citra de enero de 2024.

## Checkpoint 4 — auditoría de otras rutas dependientes de velocidad

Rutas normales revisadas que no explican crecimiento ilimitado por sí solas:

- `DspInterface::fifo`: ring buffer fijo (`0x2000`, estéreo); descarta/sobrescribe en lugar de
  crecer.
- Presentación OpenGL: pool fijo de tres `Frame`; si no hay libre, reutiliza el frame presentado
  más antiguo.
- Presentación Vulkan: los punteros de `present_queue` provienen de `swap_chain`; `GetRenderFrame`
  bloquea cuando no hay frames libres.
- Logging: cola MPSC acotada a 4096 entradas; `EmplaceWait` aplica backpressure. RPC genera dos
  mensajes `Info` por operación con el filtro por defecto, lo cual añade CPU, disco y asignaciones,
  pero no crecimiento ilimitado de esa cola.
- `PerfStats`: historial fijo de 216 000 `double`; se reserva con el objeto y deja de registrar al
  llenarse.
- Caché de superficies: tiene recolección diferida por `frame_tick`; acelerar hace que tanto la
  creación como la recolección avancen en tiempo emulado. Puede adelantar el high-water mark en
  tiempo real, pero no hay evidencia de que sea la fuga descrita.

Rutas ilimitadas condicionales, upstream, que deben excluirse en una reproducción controlada:

- IPC Recorder: si `Enable Recording` está activado, el widget guarda indefinidamente cada
  `RequestRecord` y cada `QTreeWidgetItem` hasta pulsar `Clear`. Su tasa crece con la velocidad.
- CiTrace/PICA tracing: los vectores `Recorder::stream` y `PicaTrace::writes` crecen hasta terminar
  manualmente la captura.
- Volcado de video FFmpeg: el video tiene doble buffer y backpressure, pero las dos colas de audio
  son `SPSCQueue` ilimitadas. Si el encoder de audio consume más lento que el emulador, el backlog
  crece con la velocidad.
- Vulkan `Scheduler::work_queue` es nominalmente ilimitada y recicla chunks de 32 KiB. El flujo de
  presentación y los `Finish/Wait` introducen sincronización, por lo que queda como sospechoso de
  backlog transitorio dependiente de GPU, no como causa demostrada.

## Checkpoint 5 — relación real con el control de velocidad y procedencia

`FrameLimiter::DoFrameLimiting` (`src/core/perf_stats.cpp`) no reserva memoria: al aumentar
`frame_limit` reduce la espera respecto del tiempo emulado. El efecto importante es indirecto:
se ejecutan más ticks DSP, frames gráficos, compilaciones de shaders y trabajo de CPU por segundo
de pared. Por eso una fuga por unidad de tiempo emulado, como la de AAC, presenta una pendiente
aproximadamente proporcional a la velocidad. También hace que cachés finitas por contenido alcancen
antes su punto máximo, sin convertirlas necesariamente en fugas.

El RPC UDP es un disparador separado. La velocidad del emulador no genera datagramas por sí sola.
Su cola crece cuando un cliente los produce más rápido de lo que el único hilo RPC puede leer la
memoria invitada y responder. Una velocidad alta puede empeorar la capacidad del consumidor por
contención de CPU, pero no se debe atribuir causalidad directa sin medir la tasa de entrada. Un
cliente secuencial que espera cada respuesta probablemente no acumulará cola; uno pipelined o que
continúa enviando durante stalls sí puede hacerlo.

La comparación de historial deja dos atribuciones diferentes:

- Fuga AAC: heredada íntegramente de Citra/Lime3DS; el archivo local no fue modificado por
  LimoMada3DS. Azahar la corrigió después en PR #1167.
- RPC: cola ilimitada y consumidor único heredados de upstream. El commit propio `b003e78d4`
  aumentó cada buffer de datos de 32 a 1024 bytes y amplificó el coste por elemento pendiente. No
  hay evidencia de que los cambios locales de telemetría/logging hayan introducido otra cola.

Azahar añadió posteriormente una opción para no iniciar el servidor RPC, desactivada por defecto.
Eso reduce exposición y evita crecimiento accidental cuando no se usa, pero no corrige la cola
cuando el servidor está activado.

## Notas de investigación — conclusión ejecutable

### Resumen

Hay al menos **dos problemas independientes**, no una sola fuga:

1. El crecimiento al acelerar juegos que usan AAC HLE es una **fuga real upstream**: se vuelve a
   inicializar FAAD2 por frame y se pierde el filter bank anterior. Está confirmado por inspección
   de ownership y por una reproducción aislada que no recupera memoria al cerrar.
2. El crecimiento al usar RPC UDP es un **backlog ilimitado**: cada datagrama válido puede añadir
   un `Packet` de 1072 bytes a una cola enlazada sin capacidad. La memoria se recupera al vaciarla,
   de modo que no es una fuga clásica. LimoMada3DS no creó la cola, pero el aumento de payload la
   volvió mucho más costosa.

No se reprodujo todavía el escenario completo dentro de un juego porque en el workspace no había
ROM/homebrew ni un proceso de emulación activo. Las dos causas sí quedaron demostradas en sus
componentes reales compilados: la cola/`Packet` del proyecto y el `libfaad2.a` del build. La
reproducción end-to-end debe servir para medir cuánto contribuye cada una en el caso reportado, no
para volver a demostrar que esos defectos existen.

### 1. Condiciones de reproducción recomendadas

**Velocidad/AAC**

- Usar audio HLE (valor predeterminado), RPC sin cliente y un juego con AAC continuo; Pokémon X/Y
  es el caso upstream conocido.
- Mantener la misma escena y música, sin IPC Recorder, PICA/CiTrace, video dumping ni precarga de
  texturas personalizadas.
- Ejecutar por separado a 100%, 200% y 500%, registrando cada 5 s Private Bytes, Working Set,
  tiempo emulado y tiempo de pared. Repetir con audio LLE si se dispone del firmware DSP.
- Predicción: con HLE la pendiente de Private Bytes aumenta aproximadamente en proporción a la
  velocidad; con LLE desaparece esa pendiente específica.

**RPC UDP**

- Arrancar un juego para que el servidor escuche en UDP 45987.
- Comparar un cliente secuencial (envía y espera respuesta) con uno pipelined que envía lecturas
  válidas sostenidas sin esperar. Probar velocidad normal y alta, registrando datagramas/s,
  respuestas/s, profundidad/high-water de la cola y memoria privada.
- Predicción: solo aparece crecimiento sostenido si entrada > salida. Al parar el productor, la
  cola debe drenarse y la memoria debe bajar; la sonda aislada ya confirmó esta forma.

### 2. Características para clasificar la memoria

| Caso | Forma esperada | Al detener la causa | Clasificación |
| --- | --- | --- | --- |
| AAC HLE | Lineal con frames AAC; pendiente escala con velocidad | La pendiente para al cesar AAC, pero lo ya perdido no vuelve | Fuga real |
| RPC saturado | Lineal con `datagramas recibidos - respuestas procesadas` | Se recupera al drenar la cola | Cola/buffer ilimitado |
| Shader/JIT/pipelines | Escalones ligados a contenido nuevo, luego meseta | Queda como caché útil o high-water | Caché, no demostrada como fuga |
| Allocator | Working Set puede no bajar aunque objetos mueran; Private Bytes debe analizarse | Puede conservar arenas | High-water posible, descartado en las sondas principales |

### 3. Rutas sospechosas confirmadas

- AAC: `AACDecoder::Decode` → `NeAACDecInit` por petición → `filter_bank_init` → sobrescritura de
  `hDecoder->fb`. Solo el último filter bank llega a `NeAACDecClose`.
- RPC: `UDPServer::HandleReceive` → `make_unique<Packet>` → `RPCServer::QueueRequest` →
  `SPSCQueue::Push/new ElementPtr`; un hilo ejecuta `ReadBlock` y `socket.send_to` síncrono.

### 4. Evidencia

- AAC: ~9.65 KiB perdidos por `NeAACDecInit`; 48.09 MiB privados después de 5000 llamadas y sin
  descenso tras `NeAACDecClose`. El control close/reopen se estabilizó en 1.08 MiB.
- RPC: ~1.11 KiB retenidos por solicitud; 111.84 MiB privados con 100 000 pendientes y 1.88 MiB
  después de vaciar. `sizeof(Packet) == 1072`.
- La ruta de velocidad solo cambia el tiempo de espera del limitador; no contiene una asignación
  creciente propia.

### 5. Upstream frente a LimoMada3DS

- AAC: upstream, sin participación de las modificaciones locales.
- RPC: defecto de capacidad upstream, severidad amplificada por LimoMada3DS al pasar el payload
  fijo de 32 a 1024 bytes. Los dos logs `Info` por transacción aumentan trabajo, pero la cola de
  logging está acotada y no explica la retención ilimitada.

### 6. Corrección mínima propuesta

Prioridad 1: portar el arreglo de Azahar PR #1167. Inicializar FAAD2 una vez por stream, conservar
el estado durante `Decode`, y cerrar/recrear/reconfigurar al recibir `DecoderCommand::Init`.
Conservar explícitamente la semántica de carga de savestate cubierta por el parche upstream.

Prioridad 2: acotar el RPC a una cantidad pequeña y explícita (por ejemplo 128–256 solicitudes),
rechazar/datagramas excedentes con un contador y warning rate-limited, o rearmar la recepción solo
cuando haya capacidad para que el buffer UDP del SO sea el límite. Además, separar el pequeño
payload de petición del buffer de respuesta de 1024 bytes evita pagar 1 KiB por cada lectura
pendiente. Hacer configurable el servidor y dejarlo apagado cuando no se necesite es defensa
adicional, no sustituto del límite.

En la fase inicial no se aplicaron correcciones porque el alcance era exclusivamente investigación.
La implementación fue autorizada posteriormente; sus cambios y resultados están en el checkpoint
6 al final de este documento.

### 7. Verificación de las correcciones

- Repetir la matriz 100/200/500% en el mismo punto de Pokémon X/Y durante al menos 15–30 min. La
  pendiente AAC debe quedar cerca de cero sin cambios audibles, errores de decode ni regresiones
  al cambiar música/cargar savestates.
- Ejecutar la sonda AAC con el ciclo de vida corregido y un profiler/ASan: no deben aparecer
  filter banks huérfanos ni una inicialización por frame.
- Saturar RPC por encima de la tasa de servicio durante varios minutos. La profundidad nunca debe
  superar la capacidad; memoria privada debe alcanzar una meseta y el proceso debe conservar
  capacidad de respuesta. Verificar contador de descartes y recuperación tras retirar la carga.
- Comprobar que el cliente secuencial mantiene exactamente las respuestas y límites de lectura/
  escritura existentes, y medir a 100/500% para separar contención de CPU de retención de memoria.
- Repetir Vulkan/OpenGL y HLE/LLE. Si queda una pendiente solo en una combinación, capturar heap y
  GPU allocations; eso indicaría una tercera causa, no invalida las dos ya identificadas.

## Checkpoint 6 — implementación y verificación aislada

Implementación autorizada el 2026-08-27:

- `AACDecoder` ahora conserva `sample_rate`, `num_channels` y `decoder_initialized`. Abre/configura
  un decoder desde el constructor para que las cargas de savestate que empiezan directamente con
  `EncodeDecode` sigan funcionando. `NeAACDecInit` se ejecuta solo en el primer frame del stream.
  `DecoderCommand::Init` cierra y recrea el decoder, liberando el estado del stream anterior.
- RPC conserva la `SPSCQueue` existente y su semántica de apagado, pero `QueueRequest` ya no permite
  más de 256 pendientes. Como `UDPServer` mantiene una sola cadena de recepción y la cola ya era
  single-producer/single-consumer, el chequeo de `Size()` no tiene una carrera que pueda aumentar
  la cola: el consumidor concurrente solo puede reducirla. Los excedentes se descartan.
- Los descartes RPC se contabilizan y solo se registran al alcanzar potencias de dos (1, 2, 4,
  8...), evitando que un flood convierta el log en otro amplificador de recursos.
- Se preservó el cambio local previo de `udp_server.cpp` que rechaza respuestas cuyo tamaño supera
  `MAX_PACKET_DATA_SIZE`; no formaba parte de esta edición.

Resultados de verificación:

```text
Build RelWithDebInfo:
  lime_core: OK
  tests.exe: OK
  limomada3ds.exe: OK

Suite completa:
  40 casos: 35 passed, 5 skipped por falta de dspfirm/dspaudio.cdc
  570 assertions passed

Sonda RPC, 100 000 intentos con límite 256:
  cola final: 256; accepted=256; dropped=99 744
  private: 0.98 MiB -> 1.29 MiB y permanece estable durante toda la carga
  tras drenar: 1.08 MiB

Sonda AAC, 5000 frames simulados inicializando una sola vez:
  private: 0.98 MiB al inicio, 0.98 MiB antes y después del cierre
  working set: meseta de 5.02 MiB
```

Esto elimina en las sondas las dos pendientes originales: ~9.65 KiB por frame AAC y ~1.11 KiB por
petición RPC pendiente. `clang-format --dry-run --Werror` y `git diff --check` pasan para los cuatro
archivos fuente modificados.

### Estado para retomar

Implementación compilada y verificada en componentes/suite con alta confianza. Falta únicamente la
validación end-to-end que requiere material externo no presente en el workspace: ejecutar un juego
AAC (preferiblemente Pokémon X/Y) a 100/200/500%, probar cambio de música y carga de savestate, y
saturar UDP 45987 con un cliente secuencial y otro pipelined. El árbol contenía cambios ajenos antes
de esta tarea; no revertirlos ni incluirlos automáticamente en un commit.
