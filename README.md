# Sistema Solar — Renderer por Software

Simulación del sistema solar escrita en **Zig 0.16** con **raylib-zig 6.0.0**.
La escena completa se rasteriza y sombrea en CPU, píxel por píxel. Raylib se usa
solo para la ventana, el input, los tipos de vectores y la presentación final
del framebuffer.

![Vista general del sistema](docs/screenshot.png)

## Características

- Sol + 5 planetas: Mercurio, Venus, Tierra, Marte y Júpiter.
- Órbitas y rotación propias para cada cuerpo.
- Textura procedural única por planeta (sin assets externos).
- Shader de software único por planeta.
- Iluminación real desde el Sol con terminador día/noche y ambiente.
- Rasterizador propio con z-buffer, recorte cercano y back-face culling.
- LOD con tres niveles de malla de esfera.
- Skybox procedural con estrellas distribuidas por toda la esfera.
- Movimiento de cámara en 2 ejes (plano XZ) y colisiones contra todos los cuerpos.
- Selección de planeta con transición suave de cámara.

## Controles

| Entrada | Acción |
|---|---|
| `A` / `D` o arrastrar con clic izquierdo | Orbitar horizontalmente |
| `W` / `S` o rueda del ratón | Acercar / alejar |
| `1` … `5` | Viajar a Mercurio, Venus, Tierra, Marte o Júpiter |
| `R` | Volver al Sol |
| `Esc` | Salir |

El título de la ventana muestra el cuerpo enfocado, los FPS y un recordatorio
de los controles.

## Compilación y ejecución

Requisitos: Zig 0.16.0 y las dependencias de sistema de raylib. En Debian/Ubuntu:

```sh
sudo apt install libgl1-mesa-dev libx11-dev libxrandr-dev libxi-dev \
  libxcursor-dev libxinerama-dev libasound2-dev pkg-config
```

En WSL2 con WSLg no hace falta instalar nada adicional para abrir la ventana.

```sh
zig build
zig build run
```

La primera compilación genera raylib desde el código fuente y puede tardar uno
o dos minutos. Las compilaciones posteriores son rápidas.

### Modos de diagnóstico

```sh
# Renderiza un frame a PNG sin abrir ventana:
#   --shot <archivo> [foco] [distancia]
./zig-out/bin/solar_system --shot salida.png 3 14

# Mide 600 frames sin ventana:
#   --bench [foco]
./zig-out/bin/solar_system --bench 3
```

`foco` es `0` para el Sol y `1..5` para los planetas.

## Arquitectura

```text
src/main.zig      Ventana, input, cámara, transición, colisiones y presentación
src/scene.zig     Cuerpos, órbitas, texturas procedurales, shaders y luz
src/render.zig    Framebuffer, rasterizador, z-buffer, LOD y skybox
src/math.zig      Vectores y utilidades escalares
```

### Rasterizado

Cada triángulo se transforma a espacio de cámara, se recorta contra el plano
cercano y se proyecta a pantalla. El rasterizador usa funciones de borde
incrementales y bounding box por triángulo. La profundidad se interpola como
`1/z` y se compara contra un z-buffer; la posición y las UV se interpolan de
forma perspectiva-corregida. Solo se ejecuta el shader si el píxel pasa el test
de profundidad.

El back-face culling se hace antes de proyectar: la normal de la cara debe
apuntar hacia la cámara.

### LOD

Se generan tres mallas UV de esfera compartidas por todos los cuerpos:

| Nivel | Sectores × stacks | Uso |
|---|---|---|
| 0 | 12 × 6 | cuerpos lejanos |
| 1 | 24 × 12 | distancia media |
| 2 | 48 × 24 | primeros planos |

El nivel se elige con el radio proyectado en píxeles. Como todos los cuerpos son
esferas, las mallas se reutilizan y no se duplica geometría por planeta.

### Iluminación y shaders

La luz se calcula con Lambert difuso desde el Sol, atenuación por distancia y un
término ambiente. Cada planeta tiene una rama de sombreado distinta:

- **Mercurio:** modulación por cráteres/relieve y terminador duro.
- **Venus:** nubes animadas con desplazamiento de UV.
- **Tierra:** atmósfera Fresnel azul y brillo especular en el océano.
- **Marte:** polvo animado que suaviza el terminador.
- **Júpiter:** bandas onduladas con el tiempo y resplandor de la Gran Mancha Roja.

Las texturas son de 64×32, generadas al iniciar con ruido de valor/fBm y
paletas distintas. Se muestrean con filtrado bilineal.

### Skybox

El skybox es un cubemap procedural de 6 caras × 512×512. Se generan estrellas
uniformes y una banda de polvo estelar; el muestreo por dirección es una simple
selección de cara y coordenada, sin trigonometría en el loop de píxeles. Las
estrellas quedan visibles también cerca del horizonte.

### Cámara y colisiones

La cámara mantiene una altura fija y orbita al cuerpo enfocado con yaw y
distancia; por lo tanto se mueve solo en los ejes X y Z. Al seleccionar un
planeta se elige un yaw del lado iluminado y se interpola la posición con
smoothstep.

Las colisiones usan esferas de seguridad. Si la cámara entra en el radio
horizontal permitido de un cuerpo, se empuja hacia fuera en XZ. La altura no
cambia, así que se conserva la restricción de movimiento en 2 ejes.

## Uso de Raylib

Toda la escena se escribe directamente en un buffer de CPU. Raylib no se usa
para dibujar objetos ni píxeles. La única llamada de dibujo es el blit final del
framebuffer completo a la ventana mediante `UpdateTexture` + `DrawTexturePro`.
El código incluye un comentario explicando que Raylib no expone otra API pública
para presentar un framebuffer de CPU ya renderizado.

## Rendimiento

Mediciones de `--bench` en este entorno (solo render, sin vsync ni ventana):

| Vista | ms/frame | FPS aproximados |
|---|---:|---:|
| Sol de cerca | 3.8 | 260 |
| Tierra de cerca | 1.0 | 960 |
| Júpiter de cerca | 1.5 | 675 |

La ventana interactiva está limitada a 60 FPS con `setTargetFPS(60)`. El
rendimiento se mantiene estable cerca de los objetos gracias al recorte
cercano, al z-test previo al shader y al LOD.

## Puntaje estimado

| Requisito | Puntos |
|---|---:|
| 5 planetas con textura única cada uno | 50 |
| Bonus de shader único por planeta | 5 |
| Iluminación del Sol | 10 |
| Back-face culling | 10 |
| LOD | 10 |
| Rendimiento estable | 20 |
| Skybox con estrellas | 10 |
| Colisiones | 10 |
| **Total estimado** | **125** |

No se implementan la nave propia, el movimiento 3D opcional ni el efecto warp de
fast travel. La selección de planetas con transición suave cubre el requisito de
mover la cámara entre modelos.

## Capturas

![Tierra de cerca](docs/earth.png)
