<p align="center">
  <a href="https://github.com/Dathinel/rodaje"><img src="https://raw.githubusercontent.com/Dathinel/rodaje/main/assets/marca/rodaje.svg" alt="Logotipo de Rodaje" width="104"></a>
</p>

<h1 align="center">rodaje-sonidos</h1>

<p align="center">
  Complemento opcional para <a href="https://github.com/Dathinel/rodaje">Rodaje</a>: 50 efectos de sonido sintetizados por un script propio, en WAV de 48 kHz.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-CC0_1.0-E8833A?style=flat-square&labelColor=1D1D1D" alt="Licencia CC0 1.0"></a>
  <a href="https://github.com/Dathinel/rodaje-sonidos/releases/latest"><img src="https://img.shields.io/github/v/release/Dathinel/rodaje-sonidos?style=flat-square&labelColor=1D1D1D&color=E8833A&label=versi%C3%B3n" alt="Última versión"></a>
  <img src="https://img.shields.io/badge/formato-.paquete-E8833A?style=flat-square&labelColor=1D1D1D" alt="Formato .paquete">
  <a href="https://github.com/Dathinel/rodaje"><img src="https://img.shields.io/badge/para-Rodaje-E8833A?style=flat-square&labelColor=1D1D1D" alt="Para Rodaje"></a>
</p>

Ningún sonido sale de una grabación ni de una biblioteca ajena: todos los calcula `generar.ps1` con osciladores, ruido de un generador propio con semilla fija, filtros biquad, barridos de frecuencia, FM y una reverberación sencilla. Las mismas fuentes dan los mismos bytes en cualquier equipo.

| Categoría | Sonidos | Canales |
|---|---|---|
| Golpes | bombo, golpe seco, golpe grave, madera, palmada, caja | mono |
| Swooshes | corto, medio, largo, de izquierda a derecha, de derecha a izquierda, whoosh grave, whoosh de aire, doble | estéreo |
| Clics de interfaz | clic, tic, pop, interruptor (encender y apagar), clic suave, tecla, burbuja | mono |
| Transiciones | barrido ascendente y descendente, reverso, glitch, cremallera, destello | estéreo (cremallera, mono) |
| Notificaciones | campanita, ding doble, alerta suave, éxito, error, mensaje, recordatorio | mono |
| Risers | 3, 5 y 8 s, y uno tonal de 5 s | estéreo |
| Impactos | cinematográfico, boom, golpe metálico, sub, seco, trueno lejano | estéreo (sub, mono) |
| Ambientes en bucle | lluvia, viento, tono de sala, zumbido eléctrico, ventilador (10 s, sin clic en el empalme) | estéreo |

Todos en PCM de 16 bits a 48 kHz, con pico de −2 a −20 dBFS según el tipo, sin DC y con fundidos que evitan clics.

## Instalar en Rodaje

En Rodaje, Complementos → Instalar lo baja, comprueba su firma y lo instala. A mano: descarga `rodaje-sonidos-<versión>.paquete` de las [releases](https://github.com/Dathinel/rodaje-sonidos/releases) y, en Rodaje, usa «Instalar desde archivo…» en Complementos o suéltalo sobre la biblioteca. Los sonidos aparecen en la biblioteca, en Audio: se escuchan antes de usarlos y se arrastran a la línea de tiempo.

## Construir y probar

```
powershell -NoProfile -ExecutionPolicy Bypass -File probar.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File empaquetar.ps1
```

Solo hace falta Windows PowerShell 5.1. `probar.ps1` genera todo dos veces y comprueba que den los mismos bytes, que cada elemento del manifiesto tenga su WAV (y ninguno de más), la cabecera (PCM de 16 bits, 48 kHz, 1 o 2 canales), la duración de la descripción (±1 ms), el pico, la ausencia de DC y de clics, y el empalme de los bucles. `empaquetar.ps1` deja `dist\rodaje-sonidos-<versión>.paquete` con orden y fecha fijos.

| Archivo | Qué es |
|---|---|
| `paquete.json` | Manifiesto: 50 elementos `sound` (`generar.ps1 -Manifiesto paquete.json` lo vuelve a escribir) |
| `generar.ps1` | La síntesis; escribe `sonidos/<categoría>/<id>.wav` |
| `probar.ps1` | Las pruebas |
| `empaquetar.ps1` | Arma el `.paquete` |

## Licencia

CC0 1.0 (dominio público), ver `LICENSE`: se pueden usar en cualquier video, también comercial, sin atribución. El logotipo de Rodaje es marca de su autor y no forma parte de este contenido ([TRADEMARK.md](https://github.com/Dathinel/rodaje/blob/main/TRADEMARK.md)).
