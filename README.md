# 🥖 Panadería San Carlos

Proyecto final del curso **Desarrollo Web** — Universidad Mariano Gálvez de Guatemala,
Ingeniería en Sistemas de Información, Plan Sábado (2026).
Desarrollado por **Katherin López** · Carné 3675.

Sistema web para el control de producción de pan, inventario de insumos, pedidos de sucursales
y devoluciones, con ingreso por usuario y contraseña.

## Tecnologías

| Capa | Tecnología |
|---|---|
| Frontend | HTML, CSS, JavaScript (sin librerías) |
| Backend | Java 8, Jersey 2 (REST), JWT, Maven, Tomcat |
| Base de datos | Oracle XE: tablas, paquetes y procedimientos almacenados |

## Estructura

```
PanaderiaSanCarlos/
├── PanaderiaSanCarlos.sql            ← script principal de la base (tablas, paquetes)
├── 02_paquete_web.sql                ← paquete PKG_PANADERIA_WEB
├── 03_seguridad_devoluciones.sql     ← usuarios, login y devoluciones
├── Panaderia.postman_collection.json ← pruebas de la API en Postman
├── Guia_Portada_y_Login.pdf / .docx  ← guía de dónde está cada parte
├── Como_entrar_sucursales.xlsx       ← usuarios y pasos para entrar
└── PanaderiaWeb/PLANTILLA JERSY PANEDERIAWEB/PanederiaSan/   ← proyecto NetBeans (Maven)
    ├── pom.xml
    └── src/main/
        ├── java/BACKEND/         ← controller, manager, model, utils
        ├── resources/            ← config.xml (NO se sube) y config.example.xml
        └── webapp/               ← páginas, css, js e imágenes
```

## Cómo ponerlo a funcionar

1. **Base de datos (SQL Developer):** ejecute en orden `PanaderiaSanCarlos.sql`,
   `02_paquete_web.sql` y `03_seguridad_devoluciones.sql` (Ctrl+A y F5 en cada uno).
2. **Configuración:** en `src/main/resources/` copie `config.example.xml` como `config.xml`
   y escriba su usuario, contraseña y servicio de Oracle.
3. **NetBeans:** abra la carpeta `PanederiaSan`, haga **Clean and Build** y luego **Run** (Tomcat).
4. Abra `http://localhost:8080/BACKEND/` y presione **Ctrl+F5**.

Los usuarios de prueba están en `Como_entrar_sucursales.xlsx`.
