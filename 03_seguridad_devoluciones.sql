-- =====================================================================
--  PANADERÍA SAN CARLOS - USUARIOS (LOGIN) Y DEVOLUCIONES
--  Ejecutar DESPUÉS de panaderia_completo.sql y 02_paquete_web.sql
--  En SQL Developer: abrir con la conexión PanaderiaSanCarlos y F5.
--  Se puede ejecutar varias veces (borra y vuelve a crear SOLO estas
--  tablas; no toca pedidos, panes ni insumos).
--
--  Usuarios de prueba (contraseña de todos: Panaderia2026)
--    kgalvez  -> GERENTE  (Sr. Kevin Gálvez, ve todo)
--    central, chiva, barco, heydi, terminal -> SUCURSAL (solo pedidos
--    y devoluciones de su propia sucursal)
--
--  Códigos de error nuevos:
--   -20011 usuario o contraseña incorrectos   -20014 motivo no coincide con el pedido
--   -20012 el pedido no es de su sucursal     -20015 cantidad mayor a la permitida
--   -20013 pedido aún no despachado           -20016 devolución ya resuelta
--   -20017 motivo inválido
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ---------------------------------------------------------------------
-- 1. Borrar lo anterior (si existe)
-- ---------------------------------------------------------------------
BEGIN
    FOR o IN (SELECT OBJECT_NAME, OBJECT_TYPE FROM USER_OBJECTS
              WHERE OBJECT_NAME IN ('PKG_SEGURIDAD','PKG_DEVOLUCION') AND OBJECT_TYPE = 'PACKAGE') LOOP
        EXECUTE IMMEDIATE 'DROP PACKAGE ' || o.OBJECT_NAME;
    END LOOP;
    FOR t IN (SELECT COLUMN_VALUE AS TABLA FROM TABLE(SYS.ODCIVARCHAR2LIST('DEVOLUCION','USUARIO'))) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP TABLE ' || t.TABLA || ' CASCADE CONSTRAINTS PURGE';
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
        END;
    END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- 2. Tablas
-- ---------------------------------------------------------------------
CREATE TABLE USUARIO
(
    ID_USUARIO      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    USUARIO         VARCHAR2(30)  NOT NULL,
    CLAVE_HASH      VARCHAR2(64)  NOT NULL,          -- SHA-256, nunca texto plano
    NOMBRE          VARCHAR2(100) NOT NULL,
    ROL             VARCHAR2(10)  NOT NULL,
    ID_SUCURSAL     NUMBER,
    ESTADO          VARCHAR2(10)  DEFAULT 'ACTIVO' NOT NULL,
    ULTIMO_ACCESO   DATE,
    CONSTRAINT UQ_USUARIO          UNIQUE (USUARIO),
    CONSTRAINT FK_USUARIO_SUCURSAL FOREIGN KEY (ID_SUCURSAL) REFERENCES SUCURSAL(ID_SUCURSAL),
    CONSTRAINT CK_USUARIO_ROL      CHECK (ROL IN ('GERENTE','SUCURSAL')),
    CONSTRAINT CK_USUARIO_ESTADO   CHECK (ESTADO IN ('ACTIVO','INACTIVO')),
    -- Un usuario de sucursal SIEMPRE debe tener sucursal asignada
    CONSTRAINT CK_USUARIO_SUC      CHECK (ROL <> 'SUCURSAL' OR ID_SUCURSAL IS NOT NULL)
);

CREATE TABLE DEVOLUCION
(
    ID_DEVOLUCION       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ID_PEDIDO           NUMBER NOT NULL,
    ID_PRODUCTO         NUMBER NOT NULL,
    CANTIDAD            NUMBER(10,2) NOT NULL,
    MOTIVO              VARCHAR2(15) NOT NULL,
    OBSERVACION         VARCHAR2(250),
    MONTO               NUMBER(12,2) NOT NULL,       -- nota de crédito: cantidad x precio
    ESTADO              VARCHAR2(10) DEFAULT 'PENDIENTE' NOT NULL,
    FECHA_REGISTRO      DATE DEFAULT SYSDATE NOT NULL,
    ID_USUARIO_REGISTRA NUMBER NOT NULL,
    FECHA_RESOLUCION    DATE,
    ID_USUARIO_RESUELVE NUMBER,
    CONSTRAINT FK_DEV_PEDIDO    FOREIGN KEY (ID_PEDIDO)           REFERENCES PEDIDO(ID_PEDIDO),
    CONSTRAINT FK_DEV_PRODUCTO  FOREIGN KEY (ID_PRODUCTO)         REFERENCES PRODUCTO(ID_PRODUCTO),
    CONSTRAINT FK_DEV_USR_REG   FOREIGN KEY (ID_USUARIO_REGISTRA) REFERENCES USUARIO(ID_USUARIO),
    CONSTRAINT FK_DEV_USR_RES   FOREIGN KEY (ID_USUARIO_RESUELVE) REFERENCES USUARIO(ID_USUARIO),
    CONSTRAINT CK_DEV_CANTIDAD  CHECK (CANTIDAD > 0),
    CONSTRAINT CK_DEV_MOTIVO    CHECK (MOTIVO IN ('NO_SOLICITADO','EXCEDENTE','DANADO')),
    CONSTRAINT CK_DEV_ESTADO    CHECK (ESTADO IN ('PENDIENTE','APROBADA','RECHAZADA'))
);
CREATE INDEX IX_DEV_PEDIDO ON DEVOLUCION(ID_PEDIDO);
CREATE INDEX IX_USUARIO_SUC ON USUARIO(ID_SUCURSAL);

-- ---------------------------------------------------------------------
-- 3. Usuarios iniciales. Hash = SHA256(usuario_en_minúsculas || ':' || clave)
-- ---------------------------------------------------------------------
INSERT INTO USUARIO (USUARIO, CLAVE_HASH, NOMBRE, ROL, ID_SUCURSAL)
SELECT x.USR, RAWTOHEX(STANDARD_HASH(x.USR || ':' || 'Panaderia2026', 'SHA256')), x.NOM, x.ROL,
       (SELECT ID_SUCURSAL FROM SUCURSAL WHERE NOMBRE = x.SUC)
FROM (
    SELECT 'kgalvez'  USR, 'Kevin Gálvez'       NOM, 'GERENTE'  ROL, CAST(NULL AS VARCHAR2(100)) SUC FROM DUAL UNION ALL
    SELECT 'central',      'Sucursal Central',       'SUCURSAL',     'CENTRAL'      FROM DUAL UNION ALL
    SELECT 'chiva',        'Sucursal Chiva',         'SUCURSAL',     'CHIVA'        FROM DUAL UNION ALL
    SELECT 'barco',        'Sucursal Barco',         'SUCURSAL',     'BARCO'        FROM DUAL UNION ALL
    SELECT 'heydi',        'Sucursal Heydi',         'SUCURSAL',     'HEYDI'        FROM DUAL UNION ALL
    SELECT 'terminal',     'Sucursal Terminal',      'SUCURSAL',     'TERMINAL'     FROM DUAL
) x;
COMMIT;


-- ---------------------------------------------------------------------
-- 4. PKG_SEGURIDAD: login y verificación de dueño de un pedido
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_SEGURIDAD AS
    PROCEDURE SP_LOGIN(p_usuario     IN  VARCHAR2,
                       p_clave       IN  VARCHAR2,
                       p_id_usuario  OUT NUMBER,
                       p_nombre      OUT VARCHAR2,
                       p_rol         OUT VARCHAR2,
                       p_id_sucursal OUT NUMBER,
                       p_sucursal    OUT VARCHAR2);

    PROCEDURE SP_SUCURSAL_DE_PEDIDO(p_id_pedido IN NUMBER, p_id_sucursal OUT NUMBER);
END PKG_SEGURIDAD;
/

CREATE OR REPLACE PACKAGE BODY PKG_SEGURIDAD AS

    PROCEDURE SP_LOGIN(p_usuario     IN  VARCHAR2,
                       p_clave       IN  VARCHAR2,
                       p_id_usuario  OUT NUMBER,
                       p_nombre      OUT VARCHAR2,
                       p_rol         OUT VARCHAR2,
                       p_id_sucursal OUT NUMBER,
                       p_sucursal    OUT VARCHAR2) IS
        v_usuario VARCHAR2(200) := LOWER(TRIM(SUBSTR(p_usuario, 1, 200)));
        v_hash    VARCHAR2(64);
    BEGIN
        IF v_usuario IS NULL OR p_clave IS NULL THEN
            RAISE_APPLICATION_ERROR(-20011, 'Ingrese usuario y contraseña.');
        END IF;

        SELECT RAWTOHEX(STANDARD_HASH(v_usuario || ':' || p_clave, 'SHA256')) INTO v_hash FROM DUAL;

        BEGIN
            SELECT u.ID_USUARIO, u.NOMBRE, u.ROL, u.ID_SUCURSAL, s.NOMBRE
              INTO p_id_usuario, p_nombre, p_rol, p_id_sucursal, p_sucursal
              FROM USUARIO u
              LEFT JOIN SUCURSAL s ON s.ID_SUCURSAL = u.ID_SUCURSAL
             WHERE u.USUARIO = v_usuario
               AND u.CLAVE_HASH = v_hash
               AND u.ESTADO = 'ACTIVO';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Mismo mensaje si falla usuario o clave (no revela cuál existe)
                RAISE_APPLICATION_ERROR(-20011, 'Usuario o contraseña incorrectos.');
        END;

        UPDATE USUARIO SET ULTIMO_ACCESO = SYSDATE WHERE ID_USUARIO = p_id_usuario;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_LOGIN;

    PROCEDURE SP_SUCURSAL_DE_PEDIDO(p_id_pedido IN NUMBER, p_id_sucursal OUT NUMBER) IS
    BEGIN
        SELECT ID_SUCURSAL INTO p_id_sucursal FROM PEDIDO WHERE ID_PEDIDO = p_id_pedido;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'El pedido ' || p_id_pedido || ' no existe.');
    END SP_SUCURSAL_DE_PEDIDO;

END PKG_SEGURIDAD;
/


-- ---------------------------------------------------------------------
-- 5. PKG_DEVOLUCION
--    NO_SOLICITADO: llegó un pan que NO estaba en el pedido.
--    EXCEDENTE    : llegó más cantidad de la pedida.
--    DANADO       : llegó en mal estado.
--    Al APROBAR: NO_SOLICITADO y EXCEDENTE regresan al inventario;
--                DANADO es merma (no regresa).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_DEVOLUCION AS
    PROCEDURE SP_REGISTRAR(p_id_pedido     IN  NUMBER,
                           p_id_producto   IN  NUMBER,
                           p_cantidad      IN  NUMBER,
                           p_motivo        IN  VARCHAR2,
                           p_observacion   IN  VARCHAR2,
                           p_id_usuario    IN  NUMBER,
                           p_id_sucursal   IN  NUMBER,   -- NULL = gerente (sin restricción)
                           p_id_devolucion OUT NUMBER);

    PROCEDURE SP_RESOLVER(p_id_devolucion IN NUMBER,
                          p_aprobar       IN VARCHAR2,   -- 'S' aprobar / 'N' rechazar
                          p_id_usuario    IN NUMBER);

    PROCEDURE SP_LISTAR(p_id_sucursal IN NUMBER, p_estado IN VARCHAR2, p_cursor OUT SYS_REFCURSOR);
END PKG_DEVOLUCION;
/

CREATE OR REPLACE PACKAGE BODY PKG_DEVOLUCION AS

    PROCEDURE SP_REGISTRAR(p_id_pedido     IN  NUMBER,
                           p_id_producto   IN  NUMBER,
                           p_cantidad      IN  NUMBER,
                           p_motivo        IN  VARCHAR2,
                           p_observacion   IN  VARCHAR2,
                           p_id_usuario    IN  NUMBER,
                           p_id_sucursal   IN  NUMBER,
                           p_id_devolucion OUT NUMBER) IS
        v_suc_pedido   PEDIDO.ID_SUCURSAL%TYPE;
        v_estado       PEDIDO.ESTADO%TYPE;
        v_pedida       NUMBER;
        v_ya_devuelta  NUMBER;
        v_precio       PRODUCTO.PRECIO%TYPE;
        v_nombre       PRODUCTO.NOMBRE%TYPE;
    BEGIN
        IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'La cantidad debe ser mayor que 0.');
        END IF;
        IF p_motivo IS NULL OR p_motivo NOT IN ('NO_SOLICITADO','EXCEDENTE','DANADO') THEN
            RAISE_APPLICATION_ERROR(-20017, 'Motivo inválido. Use NO_SOLICITADO, EXCEDENTE o DANADO.');
        END IF;

        -- Pedido: existe, es de la sucursal y ya salió de la fábrica
        BEGIN
            SELECT ID_SUCURSAL, ESTADO INTO v_suc_pedido, v_estado
              FROM PEDIDO WHERE ID_PEDIDO = p_id_pedido FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'El pedido ' || p_id_pedido || ' no existe.');
        END;
        IF p_id_sucursal IS NOT NULL AND v_suc_pedido <> p_id_sucursal THEN
            RAISE_APPLICATION_ERROR(-20012, 'El pedido ' || p_id_pedido || ' no pertenece a su sucursal.');
        END IF;
        IF v_estado NOT IN ('DESPACHADO','ENTREGADO') THEN
            RAISE_APPLICATION_ERROR(-20013, 'Solo se pueden devolver panes de pedidos DESPACHADOS o ENTREGADOS (este está ' || v_estado || ').');
        END IF;

        -- Producto
        BEGIN
            SELECT PRECIO, NOMBRE INTO v_precio, v_nombre FROM PRODUCTO WHERE ID_PRODUCTO = p_id_producto;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'El producto ' || p_id_producto || ' no existe.');
        END;

        SELECT NVL(SUM(CANTIDAD), 0) INTO v_pedida
          FROM PEDIDO_DETALLE WHERE ID_PEDIDO = p_id_pedido AND ID_PRODUCTO = p_id_producto;

        IF p_motivo = 'NO_SOLICITADO' THEN
            IF v_pedida > 0 THEN
                RAISE_APPLICATION_ERROR(-20014, v_nombre || ' sí estaba en el pedido. Use EXCEDENTE o DAÑADO.');
            END IF;
            SELECT NVL(SUM(CANTIDAD), 0) INTO v_ya_devuelta FROM DEVOLUCION
             WHERE ID_PEDIDO = p_id_pedido AND ID_PRODUCTO = p_id_producto
               AND MOTIVO = 'NO_SOLICITADO' AND ESTADO <> 'RECHAZADA';
            IF v_ya_devuelta > 0 THEN
                RAISE_APPLICATION_ERROR(-20015, 'Ya existe una devolución de ' || v_nombre || ' no solicitado para este pedido.');
            END IF;
        ELSE
            IF v_pedida = 0 THEN
                RAISE_APPLICATION_ERROR(-20014, v_nombre || ' no estaba en el pedido. Use NO SOLICITADO.');
            END IF;
            SELECT NVL(SUM(CANTIDAD), 0) INTO v_ya_devuelta FROM DEVOLUCION
             WHERE ID_PEDIDO = p_id_pedido AND ID_PRODUCTO = p_id_producto
               AND MOTIVO IN ('EXCEDENTE','DANADO') AND ESTADO <> 'RECHAZADA';
            IF v_ya_devuelta + p_cantidad > v_pedida THEN
                RAISE_APPLICATION_ERROR(-20015, 'Se pidieron ' || v_pedida || ' de ' || v_nombre || ' y ya hay '
                    || v_ya_devuelta || ' en devolución; no puede devolver ' || p_cantidad || ' más.');
            END IF;
        END IF;

        INSERT INTO DEVOLUCION (ID_PEDIDO, ID_PRODUCTO, CANTIDAD, MOTIVO, OBSERVACION, MONTO, ID_USUARIO_REGISTRA)
        VALUES (p_id_pedido, p_id_producto, p_cantidad, p_motivo, SUBSTR(TRIM(p_observacion), 1, 250),
                p_cantidad * v_precio, p_id_usuario)
        RETURNING ID_DEVOLUCION INTO p_id_devolucion;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_id_devolucion := NULL;
            RAISE;
    END SP_REGISTRAR;


    PROCEDURE SP_RESOLVER(p_id_devolucion IN NUMBER,
                          p_aprobar       IN VARCHAR2,
                          p_id_usuario    IN NUMBER) IS
        v_estado   DEVOLUCION.ESTADO%TYPE;
        v_motivo   DEVOLUCION.MOTIVO%TYPE;
        v_producto DEVOLUCION.ID_PRODUCTO%TYPE;
        v_cantidad DEVOLUCION.CANTIDAD%TYPE;
    BEGIN
        IF p_aprobar IS NULL OR p_aprobar NOT IN ('S','N') THEN
            RAISE_APPLICATION_ERROR(-20017, 'Indique S para aprobar o N para rechazar.');
        END IF;

        BEGIN
            SELECT ESTADO, MOTIVO, ID_PRODUCTO, CANTIDAD
              INTO v_estado, v_motivo, v_producto, v_cantidad
              FROM DEVOLUCION WHERE ID_DEVOLUCION = p_id_devolucion FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20016, 'La devolución ' || p_id_devolucion || ' no existe.');
        END;

        IF v_estado <> 'PENDIENTE' THEN
            RAISE_APPLICATION_ERROR(-20016, 'La devolución ' || p_id_devolucion || ' ya fue ' || v_estado || '.');
        END IF;

        IF p_aprobar = 'S' AND v_motivo IN ('NO_SOLICITADO','EXCEDENTE') THEN
            -- El pan regresa en buen estado: vuelve al inventario
            UPDATE PRODUCTO SET STOCK_ACTUAL = STOCK_ACTUAL + v_cantidad WHERE ID_PRODUCTO = v_producto;
        END IF;

        UPDATE DEVOLUCION
           SET ESTADO = CASE p_aprobar WHEN 'S' THEN 'APROBADA' ELSE 'RECHAZADA' END,
               FECHA_RESOLUCION = SYSDATE,
               ID_USUARIO_RESUELVE = p_id_usuario
         WHERE ID_DEVOLUCION = p_id_devolucion;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_RESOLVER;


    PROCEDURE SP_LISTAR(p_id_sucursal IN NUMBER, p_estado IN VARCHAR2, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT d.ID_DEVOLUCION, d.ID_PEDIDO, s.NOMBRE AS SUCURSAL, d.ID_PRODUCTO, pr.NOMBRE AS PRODUCTO,
                   d.CANTIDAD, d.MOTIVO, d.OBSERVACION, d.MONTO, d.ESTADO,
                   TO_CHAR(d.FECHA_REGISTRO, 'YYYY-MM-DD HH24:MI')   AS FECHA_REGISTRO,
                   ur.NOMBRE                                         AS REGISTRADO_POR,
                   TO_CHAR(d.FECHA_RESOLUCION, 'YYYY-MM-DD HH24:MI') AS FECHA_RESOLUCION
              FROM DEVOLUCION d
              JOIN PEDIDO   p  ON p.ID_PEDIDO    = d.ID_PEDIDO
              JOIN SUCURSAL s  ON s.ID_SUCURSAL  = p.ID_SUCURSAL
              JOIN PRODUCTO pr ON pr.ID_PRODUCTO = d.ID_PRODUCTO
              JOIN USUARIO  ur ON ur.ID_USUARIO  = d.ID_USUARIO_REGISTRA
             WHERE (p_id_sucursal IS NULL OR p.ID_SUCURSAL = p_id_sucursal)
               AND (p_estado      IS NULL OR d.ESTADO      = p_estado)
             ORDER BY d.ID_DEVOLUCION DESC;
    END SP_LISTAR;

END PKG_DEVOLUCION;
/


-- ---------------------------------------------------------------------
-- 6. Verificar (VALID y sin errores)
-- ---------------------------------------------------------------------
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS FROM USER_OBJECTS
 WHERE OBJECT_NAME IN ('PKG_SEGURIDAD','PKG_DEVOLUCION','USUARIO','DEVOLUCION')
 ORDER BY OBJECT_NAME, OBJECT_TYPE;
SELECT NAME, LINE, TEXT FROM USER_ERRORS WHERE NAME IN ('PKG_SEGURIDAD','PKG_DEVOLUCION');
SELECT USUARIO, NOMBRE, ROL, ID_SUCURSAL FROM USUARIO ORDER BY ID_USUARIO;


-- ---------------------------------------------------------------------
-- 7. Prueba rápida (no deja datos de prueba)
-- ---------------------------------------------------------------------
DECLARE
    v_id NUMBER; v_nom VARCHAR2(100); v_rol VARCHAR2(10); v_suc NUMBER; v_snom VARCHAR2(100);
BEGIN
    PKG_SEGURIDAD.SP_LOGIN('kgalvez', 'Panaderia2026', v_id, v_nom, v_rol, v_suc, v_snom);
    DBMS_OUTPUT.PUT_LINE('[OK] Login gerente: ' || v_nom || ' (' || v_rol || ')');

    PKG_SEGURIDAD.SP_LOGIN('CHIVA', 'Panaderia2026', v_id, v_nom, v_rol, v_suc, v_snom);
    DBMS_OUTPUT.PUT_LINE('[OK] Login sucursal: ' || v_nom || ' -> ' || v_snom);

    BEGIN
        PKG_SEGURIDAD.SP_LOGIN('kgalvez', 'clave-mala', v_id, v_nom, v_rol, v_suc, v_snom);
        DBMS_OUTPUT.PUT_LINE('[FALLO] aceptó una contraseña incorrecta');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[OK] Contraseña incorrecta rechazada: ' || SQLERRM);
    END;
END;
/
