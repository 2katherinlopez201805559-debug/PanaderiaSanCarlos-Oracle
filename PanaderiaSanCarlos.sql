-- =====================================================================
--  PANADERÍA SAN CARLOS - SCRIPT COMPLETO DE BASE DE DATOS (ORACLE)
--  1. Borra todo lo anterior
--  2. Crea tablas con restricciones de integridad
--  3. Inserta datos iniciales (insumos, panes, sucursales, recetas)
--  4. Crea el paquete PKG_PANADERIA (SP + commit/rollback + excepciones)
--  5. Ejecuta pruebas automáticas ([OK] / [FALLO])
--
--  CÓMO EJECUTAR: en SQL Developer presionar F5 ("Ejecutar script").
--  NO usar F9. Ver resultados en "Salida de script" y "Salida de DBMS".
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;


-- =====================================================================
-- 1. BORRAR TODO (no da error si las tablas aún no existen)
-- =====================================================================
BEGIN
    FOR o IN (SELECT OBJECT_NAME, OBJECT_TYPE FROM USER_OBJECTS
              WHERE OBJECT_NAME IN ('PKG_PANADERIA','V_ALERTA_STOCK')
                AND OBJECT_TYPE IN ('PACKAGE','VIEW')) LOOP
        EXECUTE IMMEDIATE 'DROP ' || o.OBJECT_TYPE || ' ' || o.OBJECT_NAME;
    END LOOP;

    -- Orden: primero las hijas, luego las padres
    FOR t IN (SELECT COLUMN_VALUE AS TABLA FROM TABLE(SYS.ODCIVARCHAR2LIST(
                 'PEDIDO_DETALLE','RECETA_DETALLE','PEDIDO','SUCURSAL','PRODUCTO','INSUMO'))) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP TABLE ' || t.TABLA || ' CASCADE CONSTRAINTS PURGE';
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE <> -942 THEN RAISE; END IF;  -- -942 = la tabla no existe
        END;
    END LOOP;
END;
/


-- =====================================================================
-- 2. CREAR TABLAS
-- =====================================================================

-- Insumos (materia prima)
CREATE TABLE INSUMO
(
    ID_INSUMO       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    NOMBRE          VARCHAR2(150) NOT NULL,
    UNIDAD_MEDIDA   VARCHAR2(20)  NOT NULL,
    STOCK_ACTUAL    NUMBER(10,3)  DEFAULT 0 NOT NULL,
    STOCK_MINIMO    NUMBER(10,3)  DEFAULT 0 NOT NULL,
    ESTADO          VARCHAR2(10)  DEFAULT 'ACTIVO' NOT NULL,
    CONSTRAINT UQ_INSUMO_NOMBRE  UNIQUE (NOMBRE),
    CONSTRAINT CK_INSUMO_STOCK   CHECK (STOCK_ACTUAL >= 0 AND STOCK_MINIMO >= 0),
    CONSTRAINT CK_INSUMO_ESTADO  CHECK (ESTADO IN ('ACTIVO','INACTIVO'))
);

-- Productos terminados (panes)
CREATE TABLE PRODUCTO
(
    ID_PRODUCTO     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    NOMBRE          VARCHAR2(150) NOT NULL,
    UNIDAD_MEDIDA   VARCHAR2(20)  NOT NULL,
    PRECIO          NUMBER(10,2)  NOT NULL,
    STOCK_ACTUAL    NUMBER(10,2)  DEFAULT 0 NOT NULL,
    STOCK_MINIMO    NUMBER(10,2)  DEFAULT 0 NOT NULL,
    ESTADO          VARCHAR2(10)  DEFAULT 'ACTIVO' NOT NULL,
    CONSTRAINT UQ_PRODUCTO_NOMBRE UNIQUE (NOMBRE),
    CONSTRAINT CK_PRODUCTO_PRECIO CHECK (PRECIO > 0),
    CONSTRAINT CK_PRODUCTO_STOCK  CHECK (STOCK_ACTUAL >= 0 AND STOCK_MINIMO >= 0),
    CONSTRAINT CK_PRODUCTO_ESTADO CHECK (ESTADO IN ('ACTIVO','INACTIVO'))
);

-- Sucursales
CREATE TABLE SUCURSAL
(
    ID_SUCURSAL   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    NOMBRE        VARCHAR2(100) NOT NULL,
    DIRECCION     VARCHAR2(200),
    TELEFONO      VARCHAR2(20),
    ESTADO        VARCHAR2(10) DEFAULT 'ACTIVO' NOT NULL,
    CONSTRAINT UQ_SUCURSAL_NOMBRE UNIQUE (NOMBRE),
    CONSTRAINT CK_SUCURSAL_ESTADO CHECK (ESTADO IN ('ACTIVO','INACTIVO'))
);

-- Pedido (encabezado)
CREATE TABLE PEDIDO
(
    ID_PEDIDO       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ID_SUCURSAL     NUMBER NOT NULL,
    FECHA_PEDIDO    DATE DEFAULT SYSDATE NOT NULL,
    FECHA_ENTREGA   DATE,
    ESTADO          VARCHAR2(15) DEFAULT 'PENDIENTE' NOT NULL,
    TOTAL           NUMBER(10,2) DEFAULT 0 NOT NULL,
    CONSTRAINT FK_PEDIDO_SUCURSAL FOREIGN KEY (ID_SUCURSAL) REFERENCES SUCURSAL(ID_SUCURSAL),
    CONSTRAINT CK_PEDIDO_ESTADO   CHECK (ESTADO IN ('PENDIENTE','DESPACHADO','ENTREGADO','CANCELADO')),
    CONSTRAINT CK_PEDIDO_TOTAL    CHECK (TOTAL >= 0)
);

-- Receta (qué insumos y cuánto lleva 1 unidad de cada pan)
CREATE TABLE RECETA_DETALLE
(
    ID_RECETA_DETALLE  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ID_PRODUCTO        NUMBER NOT NULL,
    ID_INSUMO          NUMBER NOT NULL,
    CANTIDAD           NUMBER(10,3) NOT NULL,
    CONSTRAINT FK_RECETA_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTO(ID_PRODUCTO),
    CONSTRAINT FK_RECETA_INSUMO   FOREIGN KEY (ID_INSUMO)   REFERENCES INSUMO(ID_INSUMO),
    CONSTRAINT UQ_RECETA          UNIQUE (ID_PRODUCTO, ID_INSUMO),
    CONSTRAINT CK_RECETA_CANTIDAD CHECK (CANTIDAD > 0)
);

-- Detalle del pedido
CREATE TABLE PEDIDO_DETALLE
(
    ID_PEDIDO_DETALLE  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ID_PEDIDO          NUMBER NOT NULL,
    ID_PRODUCTO        NUMBER NOT NULL,
    CANTIDAD           NUMBER(10,2) NOT NULL,
    PRECIO_UNITARIO    NUMBER(10,2) NOT NULL,
    SUBTOTAL           NUMBER(12,2) GENERATED ALWAYS AS (CANTIDAD * PRECIO_UNITARIO) VIRTUAL,
    CONSTRAINT FK_DETALLE_PEDIDO   FOREIGN KEY (ID_PEDIDO)   REFERENCES PEDIDO(ID_PEDIDO),
    CONSTRAINT FK_DETALLE_PRODUCTO FOREIGN KEY (ID_PRODUCTO) REFERENCES PRODUCTO(ID_PRODUCTO),
    CONSTRAINT CK_DETALLE_CANTIDAD CHECK (CANTIDAD > 0),
    CONSTRAINT CK_DETALLE_PRECIO   CHECK (PRECIO_UNITARIO > 0)
);

-- Índices en llaves foráneas
CREATE INDEX IX_PEDIDO_SUCURSAL   ON PEDIDO(ID_SUCURSAL);
CREATE INDEX IX_RECETA_INSUMO     ON RECETA_DETALLE(ID_INSUMO);
CREATE INDEX IX_DETALLE_PEDIDO    ON PEDIDO_DETALLE(ID_PEDIDO);
CREATE INDEX IX_DETALLE_PRODUCTO  ON PEDIDO_DETALLE(ID_PRODUCTO);


-- =====================================================================
-- 3. DATOS INICIALES
-- =====================================================================

-- Insumos
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Harina de fuerza', 'kg',     100, 20);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Harina suave',     'kg',     100, 20);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Vinagre',          'litro',   20,  5);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Leche',            'litro',   50, 10);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Jugo de fruta',    'litro',   20,  5);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Levadura fresca',  'kg',      10,  2);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Levadura seca',    'kg',      10,  2);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Azúcar',           'kg',      50, 10);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Sal',              'kg',      20,  5);
INSERT INTO INSUMO (NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO) VALUES ('Huevo',            'unidad', 200, 50);

-- Productos terminados (9 tipos de pan)
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Cubos',       'unidad', 1.00, 30);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Especial',    'unidad', 1.00, 50);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Francés',     'unidad', 1.00, 30);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Alemán',      'unidad', 1.50, 50);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Cachos',      'unidad', 1.00, 30);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Cortadas',    'unidad', 1.25, 15);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Batidas',     'unidad', 1.25, 15);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Campechanas', 'unidad', 1.50, 50);
INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_MINIMO) VALUES ('Shecas',      'unidad', 1.50, 50);

-- Sucursales
INSERT INTO SUCURSAL (NOMBRE, DIRECCION, TELEFONO) VALUES ('CENTRAL',  'Por definir', 'Por definir');
INSERT INTO SUCURSAL (NOMBRE, DIRECCION, TELEFONO) VALUES ('CHIVA',    'Por definir', 'Por definir');
INSERT INTO SUCURSAL (NOMBRE, DIRECCION, TELEFONO) VALUES ('BARCO',    'Por definir', 'Por definir');
INSERT INTO SUCURSAL (NOMBRE, DIRECCION, TELEFONO) VALUES ('HEYDI',    'Por definir', 'Por definir');
INSERT INTO SUCURSAL (NOMBRE, DIRECCION, TELEFONO) VALUES ('TERMINAL', 'Por definir', 'Por definir');

-- Recetas: cantidad de insumo por 1 unidad de pan
INSERT INTO RECETA_DETALLE (ID_PRODUCTO, ID_INSUMO, CANTIDAD)
SELECT (SELECT ID_PRODUCTO FROM PRODUCTO WHERE NOMBRE = x.PAN),
       (SELECT ID_INSUMO   FROM INSUMO   WHERE NOMBRE = x.INSUMO),
       x.CANT
FROM (
    SELECT 'Cubos'       PAN, 'Harina de fuerza' INSUMO, 0.400 CANT FROM DUAL UNION ALL
    SELECT 'Cubos',           'Levadura fresca',         0.010      FROM DUAL UNION ALL
    SELECT 'Cubos',           'Azúcar',                  0.030      FROM DUAL UNION ALL
    SELECT 'Cubos',           'Sal',                     0.005      FROM DUAL UNION ALL

    SELECT 'Especial',        'Harina de fuerza',        0.300      FROM DUAL UNION ALL
    SELECT 'Especial',        'Harina suave',            0.150      FROM DUAL UNION ALL
    SELECT 'Especial',        'Leche',                   0.100      FROM DUAL UNION ALL
    SELECT 'Especial',        'Huevo',                   1          FROM DUAL UNION ALL

    SELECT 'Francés',         'Harina de fuerza',        0.350      FROM DUAL UNION ALL
    SELECT 'Francés',         'Levadura seca',           0.008      FROM DUAL UNION ALL
    SELECT 'Francés',         'Sal',                     0.006      FROM DUAL UNION ALL
    SELECT 'Francés',         'Vinagre',                 0.005      FROM DUAL UNION ALL

    SELECT 'Alemán',          'Harina de fuerza',        0.250      FROM DUAL UNION ALL
    SELECT 'Alemán',          'Harina suave',            0.150      FROM DUAL UNION ALL
    SELECT 'Alemán',          'Azúcar',                  0.040      FROM DUAL UNION ALL
    SELECT 'Alemán',          'Huevo',                   1          FROM DUAL UNION ALL

    SELECT 'Cachos',          'Harina de fuerza',        0.300      FROM DUAL UNION ALL
    SELECT 'Cachos',          'Azúcar',                  0.025      FROM DUAL UNION ALL
    SELECT 'Cachos',          'Leche',                   0.080      FROM DUAL UNION ALL

    SELECT 'Cortadas',        'Harina suave',            0.280      FROM DUAL UNION ALL
    SELECT 'Cortadas',        'Azúcar',                  0.050      FROM DUAL UNION ALL
    SELECT 'Cortadas',        'Huevo',                   1          FROM DUAL UNION ALL

    SELECT 'Batidas',         'Harina suave',            0.250      FROM DUAL UNION ALL
    SELECT 'Batidas',         'Leche',                   0.120      FROM DUAL UNION ALL
    SELECT 'Batidas',         'Levadura fresca',         0.008      FROM DUAL UNION ALL

    SELECT 'Campechanas',     'Harina de fuerza',        0.200      FROM DUAL UNION ALL
    SELECT 'Campechanas',     'Harina suave',            0.200      FROM DUAL UNION ALL
    SELECT 'Campechanas',     'Azúcar',                  0.060      FROM DUAL UNION ALL
    SELECT 'Campechanas',     'Huevo',                   1          FROM DUAL UNION ALL

    SELECT 'Shecas',          'Harina de fuerza',        0.220      FROM DUAL UNION ALL
    SELECT 'Shecas',          'Sal',                     0.005      FROM DUAL UNION ALL
    SELECT 'Shecas',          'Levadura seca',           0.007      FROM DUAL UNION ALL
    SELECT 'Shecas',          'Jugo de fruta',           0.030      FROM DUAL
) x;

COMMIT;


-- =====================================================================
-- 4. VISTA DE ALERTAS (stock en o bajo el mínimo)
-- =====================================================================
CREATE OR REPLACE VIEW V_ALERTA_STOCK AS
SELECT 'INSUMO' AS TIPO, ID_INSUMO AS ID, NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO
FROM INSUMO   WHERE ESTADO = 'ACTIVO' AND STOCK_ACTUAL <= STOCK_MINIMO
UNION ALL
SELECT 'PRODUCTO', ID_PRODUCTO, NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO
FROM PRODUCTO WHERE ESTADO = 'ACTIVO' AND STOCK_ACTUAL <= STOCK_MINIMO;


-- =====================================================================
-- 5. PAQUETE PKG_PANADERIA
--    Códigos de error:
--    -20001 insumo insuficiente        -20005 cantidad inválida
--    -20002 producto no existe         -20006 producto sin receta
--    -20003 pan insuficiente           -20007 sucursal no existe
--    -20004 pedido no existe / estado  -20008 pedido vacío
--    -20009 insumo no existe
-- =====================================================================
CREATE OR REPLACE PACKAGE PKG_PANADERIA AS
    -- Producción
    PROCEDURE SP_PRODUCIR_PAN(p_id_producto IN NUMBER, p_cantidad IN NUMBER);
    PROCEDURE SP_REGISTRAR_COMPRA_INSUMO(p_id_insumo IN NUMBER, p_cantidad IN NUMBER);

    -- Pedidos
    PROCEDURE SP_CREAR_PEDIDO(p_id_sucursal IN NUMBER, p_fecha_entrega IN DATE, p_id_pedido OUT NUMBER);
    PROCEDURE SP_AGREGAR_DETALLE(p_id_pedido IN NUMBER, p_id_producto IN NUMBER, p_cantidad IN NUMBER);
    PROCEDURE SP_DESPACHAR_PEDIDO(p_id_pedido IN NUMBER);
    PROCEDURE SP_ENTREGAR_PEDIDO(p_id_pedido IN NUMBER);
    PROCEDURE SP_CANCELAR_PEDIDO(p_id_pedido IN NUMBER);
END PKG_PANADERIA;
/

CREATE OR REPLACE PACKAGE BODY PKG_PANADERIA AS

    -- ---------- Utilidades privadas ----------
    PROCEDURE validar_cantidad(p_cantidad IN NUMBER) IS
    BEGIN
        IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'La cantidad debe ser mayor que 0.');
        END IF;
    END validar_cantidad;

    -- Bloquea el pedido y verifica que esté en el estado esperado
    PROCEDURE validar_estado_pedido(p_id_pedido IN NUMBER, p_estado_esperado IN VARCHAR2) IS
        v_estado PEDIDO.ESTADO%TYPE;
    BEGIN
        SELECT ESTADO INTO v_estado FROM PEDIDO
        WHERE ID_PEDIDO = p_id_pedido
        FOR UPDATE;

        IF v_estado <> p_estado_esperado THEN
            RAISE_APPLICATION_ERROR(-20004, 'El pedido ' || p_id_pedido || ' está ' || v_estado
                || '; para esta operación debe estar ' || p_estado_esperado || '.');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'El pedido ' || p_id_pedido || ' no existe.');
    END validar_estado_pedido;


    -- ---------- 1. Producir pan: descuenta insumos y suma pan ----------
    PROCEDURE SP_PRODUCIR_PAN(p_id_producto IN NUMBER, p_cantidad IN NUMBER) IS
        v_existe   NUMBER;
        v_stock    INSUMO.STOCK_ACTUAL%TYPE;
        v_nombre   INSUMO.NOMBRE%TYPE;
        v_lineas   NUMBER := 0;
    BEGIN
        validar_cantidad(p_cantidad);

        SELECT COUNT(*) INTO v_existe FROM PRODUCTO
        WHERE ID_PRODUCTO = p_id_producto AND ESTADO = 'ACTIVO';
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'El producto ' || p_id_producto || ' no existe o está inactivo.');
        END IF;

        -- a) Revisar y bloquear cada insumo ANTES de modificar nada
        FOR r IN (SELECT ID_INSUMO, CANTIDAD FROM RECETA_DETALLE WHERE ID_PRODUCTO = p_id_producto) LOOP
            v_lineas := v_lineas + 1;
            SELECT STOCK_ACTUAL, NOMBRE INTO v_stock, v_nombre
            FROM INSUMO WHERE ID_INSUMO = r.ID_INSUMO
            FOR UPDATE;

            IF v_stock < r.CANTIDAD * p_cantidad THEN
                RAISE_APPLICATION_ERROR(-20001, 'Stock insuficiente de ' || v_nombre || ': hay ' || v_stock
                    || ', se necesitan ' || (r.CANTIDAD * p_cantidad) || '.');
            END IF;
        END LOOP;

        IF v_lineas = 0 THEN
            RAISE_APPLICATION_ERROR(-20006, 'El producto ' || p_id_producto || ' no tiene receta registrada.');
        END IF;

        -- b) Descontar insumos
        FOR r IN (SELECT ID_INSUMO, CANTIDAD FROM RECETA_DETALLE WHERE ID_PRODUCTO = p_id_producto) LOOP
            UPDATE INSUMO SET STOCK_ACTUAL = STOCK_ACTUAL - (r.CANTIDAD * p_cantidad)
            WHERE ID_INSUMO = r.ID_INSUMO;
        END LOOP;

        -- c) Sumar el pan producido
        UPDATE PRODUCTO SET STOCK_ACTUAL = STOCK_ACTUAL + p_cantidad
        WHERE ID_PRODUCTO = p_id_producto;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_PRODUCIR_PAN;


    -- ---------- 2. Compra de materia prima (sube stock de insumo) ----------
    PROCEDURE SP_REGISTRAR_COMPRA_INSUMO(p_id_insumo IN NUMBER, p_cantidad IN NUMBER) IS
    BEGIN
        validar_cantidad(p_cantidad);

        UPDATE INSUMO SET STOCK_ACTUAL = STOCK_ACTUAL + p_cantidad
        WHERE ID_INSUMO = p_id_insumo AND ESTADO = 'ACTIVO';

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20009, 'El insumo ' || p_id_insumo || ' no existe o está inactivo.');
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_REGISTRAR_COMPRA_INSUMO;


    -- ---------- 3. Crear pedido (encabezado) ----------
    PROCEDURE SP_CREAR_PEDIDO(p_id_sucursal IN NUMBER, p_fecha_entrega IN DATE, p_id_pedido OUT NUMBER) IS
        v_existe NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_existe FROM SUCURSAL
        WHERE ID_SUCURSAL = p_id_sucursal AND ESTADO = 'ACTIVO';
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20007, 'La sucursal ' || p_id_sucursal || ' no existe o está inactiva.');
        END IF;

        INSERT INTO PEDIDO (ID_SUCURSAL, FECHA_ENTREGA, ESTADO, TOTAL)
        VALUES (p_id_sucursal, NVL(p_fecha_entrega, TRUNC(SYSDATE) + 1), 'PENDIENTE', 0)
        RETURNING ID_PEDIDO INTO p_id_pedido;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_CREAR_PEDIDO;


    -- ---------- 4. Agregar pan a un pedido PENDIENTE ----------
    PROCEDURE SP_AGREGAR_DETALLE(p_id_pedido IN NUMBER, p_id_producto IN NUMBER, p_cantidad IN NUMBER) IS
        v_precio PRODUCTO.PRECIO%TYPE;
    BEGIN
        validar_cantidad(p_cantidad);
        validar_estado_pedido(p_id_pedido, 'PENDIENTE');

        BEGIN
            SELECT PRECIO INTO v_precio FROM PRODUCTO
            WHERE ID_PRODUCTO = p_id_producto AND ESTADO = 'ACTIVO';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20002, 'El producto ' || p_id_producto || ' no existe o está inactivo.');
        END;

        INSERT INTO PEDIDO_DETALLE (ID_PEDIDO, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
        VALUES (p_id_pedido, p_id_producto, p_cantidad, v_precio);

        UPDATE PEDIDO SET TOTAL = TOTAL + (p_cantidad * v_precio)
        WHERE ID_PEDIDO = p_id_pedido;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_AGREGAR_DETALLE;


    -- ---------- 5. Despachar: valida pan, lo descuenta y cambia estado ----------
    PROCEDURE SP_DESPACHAR_PEDIDO(p_id_pedido IN NUMBER) IS
        v_stock   PRODUCTO.STOCK_ACTUAL%TYPE;
        v_nombre  PRODUCTO.NOMBRE%TYPE;
        v_lineas  NUMBER := 0;
    BEGIN
        validar_estado_pedido(p_id_pedido, 'PENDIENTE');

        -- a) Revisar y bloquear stock de cada pan (agrupado por si se repite)
        FOR d IN (SELECT ID_PRODUCTO, SUM(CANTIDAD) AS CANTIDAD
                  FROM PEDIDO_DETALLE WHERE ID_PEDIDO = p_id_pedido
                  GROUP BY ID_PRODUCTO) LOOP
            v_lineas := v_lineas + 1;
            SELECT STOCK_ACTUAL, NOMBRE INTO v_stock, v_nombre
            FROM PRODUCTO WHERE ID_PRODUCTO = d.ID_PRODUCTO
            FOR UPDATE;

            IF v_stock < d.CANTIDAD THEN
                RAISE_APPLICATION_ERROR(-20003, 'No hay suficiente ' || v_nombre || ' producido: hay '
                    || v_stock || ', el pedido pide ' || d.CANTIDAD || '.');
            END IF;
        END LOOP;

        IF v_lineas = 0 THEN
            RAISE_APPLICATION_ERROR(-20008, 'El pedido ' || p_id_pedido || ' no tiene productos.');
        END IF;

        -- b) Descontar pan
        FOR d IN (SELECT ID_PRODUCTO, SUM(CANTIDAD) AS CANTIDAD
                  FROM PEDIDO_DETALLE WHERE ID_PEDIDO = p_id_pedido
                  GROUP BY ID_PRODUCTO) LOOP
            UPDATE PRODUCTO SET STOCK_ACTUAL = STOCK_ACTUAL - d.CANTIDAD
            WHERE ID_PRODUCTO = d.ID_PRODUCTO;
        END LOOP;

        -- c) Cambiar estado
        UPDATE PEDIDO SET ESTADO = 'DESPACHADO' WHERE ID_PEDIDO = p_id_pedido;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_DESPACHAR_PEDIDO;


    -- ---------- 6. Entregar (solo pedidos DESPACHADOS) ----------
    PROCEDURE SP_ENTREGAR_PEDIDO(p_id_pedido IN NUMBER) IS
    BEGIN
        validar_estado_pedido(p_id_pedido, 'DESPACHADO');
        UPDATE PEDIDO SET ESTADO = 'ENTREGADO' WHERE ID_PEDIDO = p_id_pedido;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_ENTREGAR_PEDIDO;


    -- ---------- 7. Cancelar (solo pedidos PENDIENTES, no toca stock) ----------
    PROCEDURE SP_CANCELAR_PEDIDO(p_id_pedido IN NUMBER) IS
    BEGIN
        validar_estado_pedido(p_id_pedido, 'PENDIENTE');
        UPDATE PEDIDO SET ESTADO = 'CANCELADO' WHERE ID_PEDIDO = p_id_pedido;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_CANCELAR_PEDIDO;

END PKG_PANADERIA;
/


-- =====================================================================
-- 6. VERIFICAR CREACIÓN
--    Esperado: 10 insumos, 9 productos, 5 sucursales, 33 recetas,
--    paquete VALID y ninguna fila en USER_ERRORS.
-- =====================================================================
SELECT 'INSUMO' TABLA, COUNT(*) FILAS FROM INSUMO UNION ALL
SELECT 'PRODUCTO',      COUNT(*) FROM PRODUCTO UNION ALL
SELECT 'SUCURSAL',      COUNT(*) FROM SUCURSAL UNION ALL
SELECT 'RECETA_DETALLE',COUNT(*) FROM RECETA_DETALLE UNION ALL
SELECT 'PEDIDO',        COUNT(*) FROM PEDIDO UNION ALL
SELECT 'PEDIDO_DETALLE',COUNT(*) FROM PEDIDO_DETALLE;

SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME IN ('PKG_PANADERIA','V_ALERTA_STOCK');

SELECT NAME, TYPE, LINE, TEXT FROM USER_ERRORS ORDER BY NAME, SEQUENCE;

-- Recetas legibles
SELECT p.NOMBRE AS PAN, i.NOMBRE AS INSUMO, r.CANTIDAD, i.UNIDAD_MEDIDA
FROM RECETA_DETALLE r
JOIN PRODUCTO p ON p.ID_PRODUCTO = r.ID_PRODUCTO
JOIN INSUMO   i ON i.ID_INSUMO   = r.ID_INSUMO
ORDER BY p.ID_PRODUCTO, i.ID_INSUMO;


-- =====================================================================
-- 7. PRUEBAS AUTOMÁTICAS
--    En Oracle NO se puede pasar (SELECT ...) como parámetro de un
--    procedimiento (error PLS-00405). Por eso primero se guardan los IDs
--    en variables con SELECT ... INTO.
-- =====================================================================
DECLARE
    v_frances   NUMBER;  v_especial NUMBER;  v_aleman NUMBER;
    v_central   NUMBER;  v_harina   NUMBER;

    v_antes     NUMBER;  v_antes2   NUMBER;  v_harina_antes NUMBER;
    v_pedido    NUMBER;  v_pedido2  NUMBER;
    v_total     NUMBER;  v_esperado NUMBER;  v_lineas NUMBER;

    v_ok        NUMBER := 0;
    v_fallos    NUMBER := 0;

    PROCEDURE chequear(p_cond BOOLEAN, p_msg VARCHAR2) IS
    BEGIN
        IF p_cond THEN
            v_ok := v_ok + 1;
            DBMS_OUTPUT.PUT_LINE('[OK]    ' || p_msg);
        ELSE
            v_fallos := v_fallos + 1;
            DBMS_OUTPUT.PUT_LINE('[FALLO] ' || p_msg);
        END IF;
    END;

    FUNCTION stock_pan(p_id NUMBER) RETURN NUMBER IS v NUMBER;
    BEGIN SELECT STOCK_ACTUAL INTO v FROM PRODUCTO WHERE ID_PRODUCTO = p_id; RETURN v; END;

    FUNCTION stock_insumo(p_id NUMBER) RETURN NUMBER IS v NUMBER;
    BEGIN SELECT STOCK_ACTUAL INTO v FROM INSUMO WHERE ID_INSUMO = p_id; RETURN v; END;

    FUNCTION estado_pedido(p_id NUMBER) RETURN VARCHAR2 IS v VARCHAR2(15);
    BEGIN SELECT ESTADO INTO v FROM PEDIDO WHERE ID_PEDIDO = p_id; RETURN v; END;
BEGIN
    SELECT ID_PRODUCTO INTO v_frances  FROM PRODUCTO WHERE NOMBRE LIKE 'Franc%';
    SELECT ID_PRODUCTO INTO v_especial FROM PRODUCTO WHERE NOMBRE = 'Especial';
    SELECT ID_PRODUCTO INTO v_aleman   FROM PRODUCTO WHERE NOMBRE LIKE 'Alem%';
    SELECT ID_SUCURSAL INTO v_central  FROM SUCURSAL WHERE NOMBRE = 'CENTRAL';
    SELECT ID_INSUMO   INTO v_harina   FROM INSUMO   WHERE NOMBRE = 'Harina de fuerza';

    DBMS_OUTPUT.PUT_LINE('===== INICIO DE PRUEBAS =====');

    -- P1: producir 50 Francés (0.350 kg harina de fuerza c/u = 17.5 kg)
    v_antes := stock_pan(v_frances);  v_harina_antes := stock_insumo(v_harina);
    PKG_PANADERIA.SP_PRODUCIR_PAN(v_frances, 50);
    chequear(stock_pan(v_frances) = v_antes + 50,
        'P1 Francés subió 50 (' || v_antes || ' -> ' || stock_pan(v_frances) || ')');
    chequear(stock_insumo(v_harina) = v_harina_antes - 17.5,
        'P1 harina de fuerza bajó 17.5 (' || v_harina_antes || ' -> ' || stock_insumo(v_harina) || ')');

    -- P2: producir sin insumos suficientes -> -20001 y nada cambia
    v_antes := stock_pan(v_frances);  v_harina_antes := stock_insumo(v_harina);
    BEGIN
        PKG_PANADERIA.SP_PRODUCIR_PAN(v_frances, 999999);
        chequear(FALSE, 'P2 debió rechazar la producción');
    EXCEPTION WHEN OTHERS THEN
        chequear(SQLCODE = -20001, 'P2 rechazada: ' || SQLERRM);
    END;
    chequear(stock_pan(v_frances) = v_antes AND stock_insumo(v_harina) = v_harina_antes,
        'P2 rollback correcto, ningún stock cambió');

    -- P3: cantidad negativa -> -20005
    BEGIN
        PKG_PANADERIA.SP_PRODUCIR_PAN(v_frances, -5);
        chequear(FALSE, 'P3 debió rechazar cantidad negativa');
    EXCEPTION WHEN OTHERS THEN
        chequear(SQLCODE = -20005, 'P3 rechazada: ' || SQLERRM);
    END;

    -- P4: crear pedido con 20 Francés + 10 Especial
    PKG_PANADERIA.SP_PRODUCIR_PAN(v_especial, 30);
    PKG_PANADERIA.SP_CREAR_PEDIDO(v_central, TRUNC(SYSDATE) + 1, v_pedido);
    chequear(v_pedido IS NOT NULL, 'P4 pedido creado con ID ' || v_pedido);
    PKG_PANADERIA.SP_AGREGAR_DETALLE(v_pedido, v_frances, 20);
    PKG_PANADERIA.SP_AGREGAR_DETALLE(v_pedido, v_especial, 10);

    SELECT 20 * (SELECT PRECIO FROM PRODUCTO WHERE ID_PRODUCTO = v_frances)
         + 10 * (SELECT PRECIO FROM PRODUCTO WHERE ID_PRODUCTO = v_especial)
      INTO v_esperado FROM DUAL;
    SELECT TOTAL INTO v_total FROM PEDIDO WHERE ID_PEDIDO = v_pedido;
    SELECT COUNT(*) INTO v_lineas FROM PEDIDO_DETALLE WHERE ID_PEDIDO = v_pedido;
    chequear(v_lineas = 2, 'P4 el pedido tiene 2 líneas');
    chequear(v_total = v_esperado, 'P4 total Q' || v_total || ' (esperado Q' || v_esperado || ')');
    chequear(estado_pedido(v_pedido) = 'PENDIENTE', 'P4 estado PENDIENTE');

    -- P5: despachar -> descuenta pan y cambia a DESPACHADO
    v_antes := stock_pan(v_frances);  v_antes2 := stock_pan(v_especial);
    PKG_PANADERIA.SP_DESPACHAR_PEDIDO(v_pedido);
    chequear(estado_pedido(v_pedido) = 'DESPACHADO', 'P5 estado DESPACHADO');
    chequear(stock_pan(v_frances) = v_antes - 20,
        'P5 Francés bajó 20 (' || v_antes || ' -> ' || stock_pan(v_frances) || ')');
    chequear(stock_pan(v_especial) = v_antes2 - 10,
        'P5 Especial bajó 10 (' || v_antes2 || ' -> ' || stock_pan(v_especial) || ')');

    -- P6: despachar dos veces el mismo pedido -> -20004 y no descuenta otra vez
    v_antes := stock_pan(v_frances);
    BEGIN
        PKG_PANADERIA.SP_DESPACHAR_PEDIDO(v_pedido);
        chequear(FALSE, 'P6 debió rechazar el segundo despacho');
    EXCEPTION WHEN OTHERS THEN
        chequear(SQLCODE = -20004, 'P6 rechazado: ' || SQLERRM);
    END;
    chequear(stock_pan(v_frances) = v_antes, 'P6 el stock no se descontó dos veces');

    -- P7: no se puede agregar pan a un pedido ya despachado
    BEGIN
        PKG_PANADERIA.SP_AGREGAR_DETALLE(v_pedido, v_frances, 5);
        chequear(FALSE, 'P7 debió rechazar agregar a pedido despachado');
    EXCEPTION WHEN OTHERS THEN
        chequear(SQLCODE = -20004, 'P7 rechazado: ' || SQLERRM);
    END;

    -- P8: entregar el pedido despachado
    PKG_PANADERIA.SP_ENTREGAR_PEDIDO(v_pedido);
    chequear(estado_pedido(v_pedido) = 'ENTREGADO', 'P8 estado ENTREGADO');

    -- P9: despachar pedido de Alemán sin producir -> -20003, sigue PENDIENTE
    PKG_PANADERIA.SP_CREAR_PEDIDO(v_central, TRUNC(SYSDATE) + 1, v_pedido2);
    PKG_PANADERIA.SP_AGREGAR_DETALLE(v_pedido2, v_aleman, 10);
    BEGIN
        PKG_PANADERIA.SP_DESPACHAR_PEDIDO(v_pedido2);
        chequear(FALSE, 'P9 debió rechazar el despacho sin pan');
    EXCEPTION WHEN OTHERS THEN
        chequear(SQLCODE = -20003, 'P9 rechazado: ' || SQLERRM);
    END;
    chequear(estado_pedido(v_pedido2) = 'PENDIENTE', 'P9 el pedido sigue PENDIENTE');

    -- P10: producto inexistente -> -20002
    BEGIN
        PKG_PANADERIA.SP_AGREGAR_DETALLE(v_pedido2, 99999, 5);
        chequear(FALSE, 'P10 debió rechazar producto inexistente');
    EXCEPTION WHEN OTHERS THEN
        chequear(SQLCODE = -20002, 'P10 rechazado: ' || SQLERRM);
    END;

    -- P11: sucursal inexistente -> -20007
    BEGIN
        PKG_PANADERIA.SP_CREAR_PEDIDO(99999, SYSDATE + 1, v_pedido);
        chequear(FALSE, 'P11 debió rechazar sucursal inexistente');
    EXCEPTION WHEN OTHERS THEN
        chequear(SQLCODE = -20007, 'P11 rechazado: ' || SQLERRM);
    END;

    -- P12: cancelar pedido pendiente
    PKG_PANADERIA.SP_CANCELAR_PEDIDO(v_pedido2);
    chequear(estado_pedido(v_pedido2) = 'CANCELADO', 'P12 estado CANCELADO');

    -- P13: compra de insumo suma al stock
    v_harina_antes := stock_insumo(v_harina);
    PKG_PANADERIA.SP_REGISTRAR_COMPRA_INSUMO(v_harina, 25);
    chequear(stock_insumo(v_harina) = v_harina_antes + 25,
        'P13 harina subió 25 (' || v_harina_antes || ' -> ' || stock_insumo(v_harina) || ')');

    DBMS_OUTPUT.PUT_LINE('===== RESULTADO: ' || v_ok || ' OK, ' || v_fallos || ' FALLO(S) =====');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/


-- =====================================================================
-- 8. VER RESULTADOS
-- =====================================================================
SELECT p.ID_PEDIDO, s.NOMBRE AS SUCURSAL, p.FECHA_PEDIDO, p.FECHA_ENTREGA, p.ESTADO, p.TOTAL
FROM PEDIDO p JOIN SUCURSAL s ON s.ID_SUCURSAL = p.ID_SUCURSAL
ORDER BY p.ID_PEDIDO;

SELECT pd.ID_PEDIDO, pr.NOMBRE AS PAN, pd.CANTIDAD, pd.PRECIO_UNITARIO, pd.SUBTOTAL
FROM PEDIDO_DETALLE pd JOIN PRODUCTO pr ON pr.ID_PRODUCTO = pd.ID_PRODUCTO
ORDER BY pd.ID_PEDIDO, pd.ID_PEDIDO_DETALLE;

SELECT NOMBRE, STOCK_ACTUAL, STOCK_MINIMO FROM PRODUCTO ORDER BY ID_PRODUCTO;
SELECT NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO FROM INSUMO ORDER BY ID_INSUMO;

-- Panes/insumos en o bajo el mínimo (alertas)
SELECT * FROM V_ALERTA_STOCK ORDER BY TIPO, NOMBRE;


-- =====================================================================
-- (OPCIONAL) Dejar la base limpia para la presentación.
-- Quita /* y */ y ejecuta este bloque para borrar los pedidos de prueba
-- y regresar los stocks a su valor inicial.
-- =====================================================================
/*
DELETE FROM PEDIDO_DETALLE;
DELETE FROM PEDIDO;
UPDATE PRODUCTO SET STOCK_ACTUAL = 0;
UPDATE INSUMO SET STOCK_ACTUAL = CASE
    WHEN NOMBRE IN ('Harina de fuerza','Harina suave') THEN 100
    WHEN NOMBRE IN ('Vinagre','Jugo de fruta','Sal')   THEN 20
    WHEN NOMBRE IN ('Leche','Azúcar')                  THEN 50
    WHEN NOMBRE IN ('Levadura fresca','Levadura seca') THEN 10
    WHEN NOMBRE = 'Huevo'                              THEN 200
    ELSE STOCK_ACTUAL END;
COMMIT;
*/






   SELECT USER FROM DUAL;

   SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
   FROM USER_OBJECTS
   WHERE OBJECT_NAME IN ('PKG_PANADERIA','PKG_PANADERIA_WEB','PRODUCTO');