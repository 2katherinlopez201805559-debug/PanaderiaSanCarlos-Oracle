-- =====================================================================
--  PANADERÍA SAN CARLOS - NUEVOS PANES, RECETAS Y PAGOS
--  Ejecutar DESPUÉS de:
--     1) PanaderiaSanCarlos.sql
--     2) 02_paquete_web.sql
--     3) 03_seguridad_devoluciones.sql
--  En SQL Developer: Ctrl+A y F5. Se puede ejecutar varias veces
--  (borra y vuelve a crear SOLO la tabla PAGO y los paquetes
--  PKG_CATALOGO y PKG_PAGO; no toca panes, recetas ni pedidos).
--
--  GERENCIA
--    * Crear un pan nuevo junto con su receta (una sola transacción).
--    * Cambiar la receta, el precio, el mínimo o activar/desactivar un pan.
--    * Revisar y confirmar/rechazar los pagos de las sucursales.
--
--  SUCURSALES - formas de pago
--    EFECTIVO       se entrega al repartidor; gerencia lo confirma al recibirlo.
--    TRANSFERENCIA  banca en línea / app del banco: banco + No. de transferencia.
--    DEPOSITO       depósito en agencia del banco: banco + No. de boleta.
--    TARJETA        débito o crédito por POS o link de pago: No. de autorización
--                   del voucher. (El sistema NUNCA guarda números de tarjeta.)
--
--  Saldo de un pedido = TOTAL - devoluciones APROBADAS (nota de crédito)
--                             - pagos CONFIRMADOS
--
--  Códigos de error nuevos:
--   -20018 datos del pan inválidos o nombre repetido
--   -20019 receta inválida (vacía, formato, insumo repetido)
--   -20020 forma de pago inválida
--   -20021 monto inválido o mayor al saldo pendiente
--   -20022 falta la referencia / referencia ya usada
--   -20023 el pedido no se puede pagar (cancelado o ya pagado)
--   -20024 el pago no existe o ya fue revisado
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ---------------------------------------------------------------------
-- 1. Borrar lo anterior (si existe)
-- ---------------------------------------------------------------------
BEGIN
    FOR o IN (SELECT OBJECT_NAME FROM USER_OBJECTS
              WHERE OBJECT_NAME IN ('PKG_CATALOGO','PKG_PAGO') AND OBJECT_TYPE = 'PACKAGE') LOOP
        EXECUTE IMMEDIATE 'DROP PACKAGE ' || o.OBJECT_NAME;
    END LOOP;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE PAGO CASCADE CONSTRAINTS PURGE';
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
END;
/

-- ---------------------------------------------------------------------
-- 2. Tabla PAGO
-- ---------------------------------------------------------------------
CREATE TABLE PAGO
(
    ID_PAGO             NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ID_PEDIDO           NUMBER        NOT NULL,
    METODO              VARCHAR2(15)  NOT NULL,
    MONTO               NUMBER(12,2)  NOT NULL,
    BANCO               VARCHAR2(60),
    REFERENCIA          VARCHAR2(40),             -- No. transferencia / boleta / autorización
    OBSERVACION         VARCHAR2(250),
    ESTADO              VARCHAR2(10)  DEFAULT 'PENDIENTE' NOT NULL,
    FECHA_REGISTRO      DATE          DEFAULT SYSDATE NOT NULL,
    ID_USUARIO_REGISTRA NUMBER        NOT NULL,
    FECHA_RESOLUCION    DATE,
    ID_USUARIO_RESUELVE NUMBER,
    CONSTRAINT FK_PAGO_PEDIDO  FOREIGN KEY (ID_PEDIDO)           REFERENCES PEDIDO(ID_PEDIDO),
    CONSTRAINT FK_PAGO_USR_REG FOREIGN KEY (ID_USUARIO_REGISTRA) REFERENCES USUARIO(ID_USUARIO),
    CONSTRAINT FK_PAGO_USR_RES FOREIGN KEY (ID_USUARIO_RESUELVE) REFERENCES USUARIO(ID_USUARIO),
    CONSTRAINT CK_PAGO_METODO  CHECK (METODO IN ('EFECTIVO','TRANSFERENCIA','DEPOSITO','TARJETA')),
    CONSTRAINT CK_PAGO_MONTO   CHECK (MONTO > 0),
    CONSTRAINT CK_PAGO_ESTADO  CHECK (ESTADO IN ('PENDIENTE','CONFIRMADO','RECHAZADO')),
    -- Todo pago que no sea en efectivo debe traer su número de referencia
    CONSTRAINT CK_PAGO_REF     CHECK (METODO = 'EFECTIVO' OR REFERENCIA IS NOT NULL)
);
CREATE INDEX IX_PAGO_PEDIDO ON PAGO(ID_PEDIDO);


-- ---------------------------------------------------------------------
-- 3. PKG_CATALOGO: panes nuevos y recetas
--    La receta llega como texto "idInsumo:cantidad;idInsumo:cantidad"
--    (ej. "1:0.350;7:0.008;9:0.006") para guardar el pan y TODA su
--    receta en UNA sola transacción.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_CATALOGO AS
    PROCEDURE SP_CREAR_PAN(p_nombre        IN  VARCHAR2,
                           p_unidad        IN  VARCHAR2,
                           p_precio        IN  NUMBER,
                           p_stock_minimo  IN  NUMBER,
                           p_receta        IN  VARCHAR2,
                           p_id_producto   OUT NUMBER);

    PROCEDURE SP_GUARDAR_RECETA(p_id_producto IN NUMBER, p_receta IN VARCHAR2);

    PROCEDURE SP_ACTUALIZAR_PAN(p_id_producto  IN NUMBER,
                                p_precio       IN NUMBER,
                                p_stock_minimo IN NUMBER,
                                p_estado       IN VARCHAR2);
END PKG_CATALOGO;
/

CREATE OR REPLACE PACKAGE BODY PKG_CATALOGO AS

    -- Borra la receta actual del pan y la vuelve a cargar desde el texto.
    -- NO hace COMMIT: lo hace el procedimiento público que la llama.
    PROCEDURE cargar_receta(p_id_producto IN NUMBER, p_receta IN VARCHAR2) IS
        v_total   PLS_INTEGER;
        v_par     VARCHAR2(100);
        v_id      NUMBER;
        v_cant    NUMBER;
        v_estado  INSUMO.ESTADO%TYPE;
        v_nombre  INSUMO.NOMBRE%TYPE;
    BEGIN
        v_total := NVL(REGEXP_COUNT(p_receta, '[^;]+'), 0);
        IF v_total = 0 THEN
            RAISE_APPLICATION_ERROR(-20019, 'La receta debe tener al menos un insumo.');
        END IF;

        DELETE FROM RECETA_DETALLE WHERE ID_PRODUCTO = p_id_producto;

        FOR i IN 1 .. v_total LOOP
            v_par := TRIM(REGEXP_SUBSTR(p_receta, '[^;]+', 1, i));
            IF INSTR(v_par, ':') = 0 THEN
                RAISE_APPLICATION_ERROR(-20019, 'Formato de receta inválido en "' || v_par || '".');
            END IF;
            BEGIN
                v_id   := TO_NUMBER(TRIM(SUBSTR(v_par, 1, INSTR(v_par, ':') - 1)));
                v_cant := TO_NUMBER(TRIM(SUBSTR(v_par, INSTR(v_par, ':') + 1)),
                                    '999999990D999999', 'NLS_NUMERIC_CHARACTERS=''.,''');
            EXCEPTION WHEN VALUE_ERROR OR INVALID_NUMBER THEN
                RAISE_APPLICATION_ERROR(-20019, 'Formato de receta inválido en "' || v_par || '".');
            END;

            BEGIN
                SELECT ESTADO, NOMBRE INTO v_estado, v_nombre FROM INSUMO WHERE ID_INSUMO = v_id;
            EXCEPTION WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20009, 'El insumo ' || v_id || ' no existe.');
            END;
            IF v_estado <> 'ACTIVO' THEN
                RAISE_APPLICATION_ERROR(-20009, 'El insumo ' || v_nombre || ' está inactivo.');
            END IF;
            IF v_cant IS NULL OR v_cant <= 0 THEN
                RAISE_APPLICATION_ERROR(-20005, 'La cantidad de ' || v_nombre || ' debe ser mayor que 0.');
            END IF;

            BEGIN
                INSERT INTO RECETA_DETALLE (ID_PRODUCTO, ID_INSUMO, CANTIDAD)
                VALUES (p_id_producto, v_id, v_cant);
            EXCEPTION WHEN DUP_VAL_ON_INDEX THEN
                RAISE_APPLICATION_ERROR(-20019, 'El insumo ' || v_nombre || ' está repetido en la receta.');
            END;
        END LOOP;
    END cargar_receta;


    PROCEDURE SP_CREAR_PAN(p_nombre        IN  VARCHAR2,
                           p_unidad        IN  VARCHAR2,
                           p_precio        IN  NUMBER,
                           p_stock_minimo  IN  NUMBER,
                           p_receta        IN  VARCHAR2,
                           p_id_producto   OUT NUMBER) IS
        v_nombre  VARCHAR2(150) := TRIM(p_nombre);
        v_existe  NUMBER;
    BEGIN
        IF v_nombre IS NULL OR LENGTH(v_nombre) < 3 THEN
            RAISE_APPLICATION_ERROR(-20018, 'El nombre del pan debe tener al menos 3 letras.');
        END IF;
        IF p_precio IS NULL OR p_precio <= 0 THEN
            RAISE_APPLICATION_ERROR(-20018, 'El precio debe ser mayor que 0.');
        END IF;
        IF p_stock_minimo IS NULL OR p_stock_minimo < 0 THEN
            RAISE_APPLICATION_ERROR(-20018, 'La existencia mínima no puede ser negativa.');
        END IF;

        SELECT COUNT(*) INTO v_existe FROM PRODUCTO WHERE UPPER(NOMBRE) = UPPER(v_nombre);
        IF v_existe > 0 THEN
            RAISE_APPLICATION_ERROR(-20018, 'Ya existe un pan llamado ' || v_nombre || '.');
        END IF;

        INSERT INTO PRODUCTO (NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_ACTUAL, STOCK_MINIMO, ESTADO)
        VALUES (v_nombre, NVL(TRIM(p_unidad), 'unidad'), p_precio, 0, p_stock_minimo, 'ACTIVO')
        RETURNING ID_PRODUCTO INTO p_id_producto;

        cargar_receta(p_id_producto, p_receta);

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_id_producto := NULL;
            RAISE;
    END SP_CREAR_PAN;


    PROCEDURE SP_GUARDAR_RECETA(p_id_producto IN NUMBER, p_receta IN VARCHAR2) IS
        v_existe NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_existe FROM PRODUCTO WHERE ID_PRODUCTO = p_id_producto;
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'El producto ' || p_id_producto || ' no existe.');
        END IF;

        cargar_receta(p_id_producto, p_receta);

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_GUARDAR_RECETA;


    PROCEDURE SP_ACTUALIZAR_PAN(p_id_producto  IN NUMBER,
                                p_precio       IN NUMBER,
                                p_stock_minimo IN NUMBER,
                                p_estado       IN VARCHAR2) IS
    BEGIN
        IF p_precio IS NULL OR p_precio <= 0 THEN
            RAISE_APPLICATION_ERROR(-20018, 'El precio debe ser mayor que 0.');
        END IF;
        IF p_stock_minimo IS NULL OR p_stock_minimo < 0 THEN
            RAISE_APPLICATION_ERROR(-20018, 'La existencia mínima no puede ser negativa.');
        END IF;
        IF p_estado IS NULL OR p_estado NOT IN ('ACTIVO','INACTIVO') THEN
            RAISE_APPLICATION_ERROR(-20018, 'El estado debe ser ACTIVO o INACTIVO.');
        END IF;

        UPDATE PRODUCTO
           SET PRECIO = p_precio, STOCK_MINIMO = p_stock_minimo, ESTADO = p_estado
         WHERE ID_PRODUCTO = p_id_producto;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'El producto ' || p_id_producto || ' no existe.');
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_ACTUALIZAR_PAN;

END PKG_CATALOGO;
/


-- ---------------------------------------------------------------------
-- 4. PKG_PAGO: pagos de pedidos
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_PAGO AS
    -- p_id_sucursal NULL = lo registra gerencia (queda CONFIRMADO).
    -- Con sucursal = lo registra la sucursal (queda PENDIENTE de revisión).
    PROCEDURE SP_REGISTRAR(p_id_pedido   IN  NUMBER,
                           p_metodo      IN  VARCHAR2,
                           p_monto       IN  NUMBER,
                           p_banco       IN  VARCHAR2,
                           p_referencia  IN  VARCHAR2,
                           p_observacion IN  VARCHAR2,
                           p_id_usuario  IN  NUMBER,
                           p_id_sucursal IN  NUMBER,
                           p_id_pago     OUT NUMBER);

    PROCEDURE SP_RESOLVER(p_id_pago IN NUMBER, p_aprobar IN VARCHAR2, p_id_usuario IN NUMBER);

    PROCEDURE SP_LISTAR(p_id_sucursal IN NUMBER, p_estado IN VARCHAR2, p_cursor OUT SYS_REFCURSOR);

    -- Pedidos con total, crédito por devoluciones, pagado y saldo
    PROCEDURE SP_ESTADO_CUENTA(p_id_sucursal IN NUMBER, p_cursor OUT SYS_REFCURSOR);
END PKG_PAGO;
/

CREATE OR REPLACE PACKAGE BODY PKG_PAGO AS

    FUNCTION credito_devoluciones(p_id_pedido NUMBER) RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT NVL(SUM(MONTO), 0) INTO v FROM DEVOLUCION
         WHERE ID_PEDIDO = p_id_pedido AND ESTADO = 'APROBADA';
        RETURN v;
    END credito_devoluciones;

    -- Pagos que ya cuentan: confirmados + los que están en revisión
    FUNCTION pagos_vigentes(p_id_pedido NUMBER) RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT NVL(SUM(MONTO), 0) INTO v FROM PAGO
         WHERE ID_PEDIDO = p_id_pedido AND ESTADO IN ('PENDIENTE','CONFIRMADO');
        RETURN v;
    END pagos_vigentes;


    PROCEDURE SP_REGISTRAR(p_id_pedido   IN  NUMBER,
                           p_metodo      IN  VARCHAR2,
                           p_monto       IN  NUMBER,
                           p_banco       IN  VARCHAR2,
                           p_referencia  IN  VARCHAR2,
                           p_observacion IN  VARCHAR2,
                           p_id_usuario  IN  NUMBER,
                           p_id_sucursal IN  NUMBER,
                           p_id_pago     OUT NUMBER) IS
        v_suc        PEDIDO.ID_SUCURSAL%TYPE;
        v_estado     PEDIDO.ESTADO%TYPE;
        v_total      PEDIDO.TOTAL%TYPE;
        v_disponible NUMBER;
        v_metodo     VARCHAR2(15) := UPPER(TRIM(p_metodo));
        v_banco      VARCHAR2(60) := TRIM(p_banco);
        v_ref        VARCHAR2(40) := UPPER(TRIM(p_referencia));
        v_repetida   NUMBER;
    BEGIN
        IF v_metodo IS NULL OR v_metodo NOT IN ('EFECTIVO','TRANSFERENCIA','DEPOSITO','TARJETA') THEN
            RAISE_APPLICATION_ERROR(-20020, 'Forma de pago inválida. Use EFECTIVO, TRANSFERENCIA, DEPOSITO o TARJETA.');
        END IF;
        IF p_monto IS NULL OR p_monto <= 0 THEN
            RAISE_APPLICATION_ERROR(-20021, 'El monto debe ser mayor que 0.');
        END IF;
        IF ROUND(p_monto, 2) <> p_monto THEN
            RAISE_APPLICATION_ERROR(-20021, 'El monto admite máximo 2 decimales.');
        END IF;

        IF v_metodo IN ('TRANSFERENCIA','DEPOSITO') AND v_banco IS NULL THEN
            RAISE_APPLICATION_ERROR(-20022, 'Seleccione el banco.');
        END IF;
        IF v_metodo <> 'EFECTIVO' THEN
            IF v_ref IS NULL OR LENGTH(v_ref) < 4 THEN
                RAISE_APPLICATION_ERROR(-20022, 'Escriba el número de referencia (mínimo 4 caracteres).');
            END IF;
            -- La misma transferencia / boleta / autorización no se puede usar dos veces
            SELECT COUNT(*) INTO v_repetida FROM PAGO
             WHERE METODO = v_metodo AND NVL(BANCO, '-') = NVL(v_banco, '-')
               AND REFERENCIA = v_ref AND ESTADO <> 'RECHAZADO';
            IF v_repetida > 0 THEN
                RAISE_APPLICATION_ERROR(-20022, 'La referencia ' || v_ref || ' ya fue registrada en otro pago.');
            END IF;
        ELSE
            v_ref := NULL;
            v_banco := NULL;
        END IF;

        BEGIN
            SELECT ID_SUCURSAL, ESTADO, TOTAL INTO v_suc, v_estado, v_total
              FROM PEDIDO WHERE ID_PEDIDO = p_id_pedido FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'El pedido ' || p_id_pedido || ' no existe.');
        END;
        IF p_id_sucursal IS NOT NULL AND v_suc <> p_id_sucursal THEN
            RAISE_APPLICATION_ERROR(-20012, 'El pedido ' || p_id_pedido || ' no pertenece a su sucursal.');
        END IF;
        IF v_estado = 'CANCELADO' THEN
            RAISE_APPLICATION_ERROR(-20023, 'El pedido ' || p_id_pedido || ' está cancelado; no se puede pagar.');
        END IF;

        v_disponible := v_total - credito_devoluciones(p_id_pedido) - pagos_vigentes(p_id_pedido);
        IF v_disponible <= 0 THEN
            RAISE_APPLICATION_ERROR(-20023, 'El pedido ' || p_id_pedido || ' ya está pagado (o tiene pagos en revisión por el total).');
        END IF;
        IF p_monto > v_disponible THEN
            RAISE_APPLICATION_ERROR(-20021, 'El monto (Q ' || TO_CHAR(p_monto, 'FM999G990D00') ||
                ') es mayor al saldo pendiente (Q ' || TO_CHAR(v_disponible, 'FM999G990D00') || ').');
        END IF;

        INSERT INTO PAGO (ID_PEDIDO, METODO, MONTO, BANCO, REFERENCIA, OBSERVACION, ESTADO,
                          ID_USUARIO_REGISTRA, FECHA_RESOLUCION, ID_USUARIO_RESUELVE)
        VALUES (p_id_pedido, v_metodo, p_monto, v_banco, v_ref, SUBSTR(TRIM(p_observacion), 1, 250),
                CASE WHEN p_id_sucursal IS NULL THEN 'CONFIRMADO' ELSE 'PENDIENTE' END,
                p_id_usuario,
                CASE WHEN p_id_sucursal IS NULL THEN SYSDATE END,
                CASE WHEN p_id_sucursal IS NULL THEN p_id_usuario END)
        RETURNING ID_PAGO INTO p_id_pago;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_id_pago := NULL;
            RAISE;
    END SP_REGISTRAR;


    PROCEDURE SP_RESOLVER(p_id_pago IN NUMBER, p_aprobar IN VARCHAR2, p_id_usuario IN NUMBER) IS
        v_estado PAGO.ESTADO%TYPE;
    BEGIN
        IF p_aprobar IS NULL OR p_aprobar NOT IN ('S','N') THEN
            RAISE_APPLICATION_ERROR(-20024, 'Indique S para confirmar o N para rechazar.');
        END IF;
        BEGIN
            SELECT ESTADO INTO v_estado FROM PAGO WHERE ID_PAGO = p_id_pago FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20024, 'El pago ' || p_id_pago || ' no existe.');
        END;
        IF v_estado <> 'PENDIENTE' THEN
            RAISE_APPLICATION_ERROR(-20024, 'El pago ' || p_id_pago || ' ya fue ' || v_estado || '.');
        END IF;

        UPDATE PAGO
           SET ESTADO = CASE p_aprobar WHEN 'S' THEN 'CONFIRMADO' ELSE 'RECHAZADO' END,
               FECHA_RESOLUCION = SYSDATE,
               ID_USUARIO_RESUELVE = p_id_usuario
         WHERE ID_PAGO = p_id_pago;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END SP_RESOLVER;


    PROCEDURE SP_LISTAR(p_id_sucursal IN NUMBER, p_estado IN VARCHAR2, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT pg.ID_PAGO, pg.ID_PEDIDO, s.NOMBRE AS SUCURSAL, pg.METODO, pg.MONTO, pg.BANCO,
                   pg.REFERENCIA, pg.OBSERVACION, pg.ESTADO,
                   TO_CHAR(pg.FECHA_REGISTRO, 'YYYY-MM-DD HH24:MI')   AS FECHA_REGISTRO,
                   ur.NOMBRE                                          AS REGISTRADO_POR,
                   TO_CHAR(pg.FECHA_RESOLUCION, 'YYYY-MM-DD HH24:MI') AS FECHA_RESOLUCION
              FROM PAGO pg
              JOIN PEDIDO   p  ON p.ID_PEDIDO   = pg.ID_PEDIDO
              JOIN SUCURSAL s  ON s.ID_SUCURSAL = p.ID_SUCURSAL
              JOIN USUARIO  ur ON ur.ID_USUARIO = pg.ID_USUARIO_REGISTRA
             WHERE (p_id_sucursal IS NULL OR p.ID_SUCURSAL = p_id_sucursal)
               AND (p_estado      IS NULL OR pg.ESTADO     = p_estado)
             ORDER BY pg.ID_PAGO DESC;
    END SP_LISTAR;


    PROCEDURE SP_ESTADO_CUENTA(p_id_sucursal IN NUMBER, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT x.*,
                   x.TOTAL - x.CREDITO - x.PAGADO                AS SALDO,
                   x.TOTAL - x.CREDITO - x.PAGADO - x.EN_REVISION AS POR_PAGAR,
                   CASE
                       WHEN x.TOTAL - x.CREDITO - x.PAGADO <= 0               THEN 'PAGADO'
                       WHEN x.TOTAL - x.CREDITO - x.PAGADO - x.EN_REVISION <= 0 THEN 'EN_REVISION'
                       WHEN x.PAGADO + x.EN_REVISION > 0                       THEN 'PARCIAL'
                       ELSE 'SIN_PAGO'
                   END AS ESTADO_PAGO
              FROM (
                    SELECT p.ID_PEDIDO, p.ID_SUCURSAL, s.NOMBRE AS SUCURSAL, p.ESTADO,
                           TO_CHAR(p.FECHA_ENTREGA, 'YYYY-MM-DD') AS FECHA_ENTREGA,
                           p.TOTAL,
                           NVL((SELECT SUM(d.MONTO) FROM DEVOLUCION d
                                 WHERE d.ID_PEDIDO = p.ID_PEDIDO AND d.ESTADO = 'APROBADA'), 0)   AS CREDITO,
                           NVL((SELECT SUM(g.MONTO) FROM PAGO g
                                 WHERE g.ID_PEDIDO = p.ID_PEDIDO AND g.ESTADO = 'CONFIRMADO'), 0) AS PAGADO,
                           NVL((SELECT SUM(g.MONTO) FROM PAGO g
                                 WHERE g.ID_PEDIDO = p.ID_PEDIDO AND g.ESTADO = 'PENDIENTE'), 0)  AS EN_REVISION
                      FROM PEDIDO p
                      JOIN SUCURSAL s ON s.ID_SUCURSAL = p.ID_SUCURSAL
                     WHERE p.ESTADO <> 'CANCELADO'
                       AND (p_id_sucursal IS NULL OR p.ID_SUCURSAL = p_id_sucursal)
                   ) x
             ORDER BY x.ID_PEDIDO DESC;
    END SP_ESTADO_CUENTA;

END PKG_PAGO;
/


-- ---------------------------------------------------------------------
-- 5. Verificar (todo VALID y sin errores)
-- ---------------------------------------------------------------------
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS FROM USER_OBJECTS
 WHERE OBJECT_NAME IN ('PKG_CATALOGO','PKG_PAGO','PAGO')
 ORDER BY OBJECT_NAME, OBJECT_TYPE;
SELECT NAME, LINE, TEXT FROM USER_ERRORS WHERE NAME IN ('PKG_CATALOGO','PKG_PAGO');


-- ---------------------------------------------------------------------
-- 6. Prueba rápida: valida reglas SIN dejar datos de prueba
-- ---------------------------------------------------------------------
DECLARE
    v_id NUMBER;
BEGIN
    BEGIN
        PKG_CATALOGO.SP_CREAR_PAN('Pan de prueba', 'unidad', 1.00, 10, '', v_id);
        DBMS_OUTPUT.PUT_LINE('[FALLO] aceptó un pan sin receta');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[OK] Pan sin receta rechazado: ' || SQLERRM);
    END;

    BEGIN
        PKG_CATALOGO.SP_CREAR_PAN('Francés', 'unidad', 1.00, 10, '1:0.3', v_id);
        DBMS_OUTPUT.PUT_LINE('[FALLO] aceptó un nombre repetido');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[OK] Nombre repetido rechazado: ' || SQLERRM);
    END;

    BEGIN
        PKG_PAGO.SP_REGISTRAR(-1, 'BITCOIN', 10, NULL, NULL, NULL, 1, NULL, v_id);
        DBMS_OUTPUT.PUT_LINE('[FALLO] aceptó una forma de pago inválida');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[OK] Forma de pago inválida rechazada: ' || SQLERRM);
    END;

    BEGIN
        PKG_PAGO.SP_REGISTRAR(-1, 'TRANSFERENCIA', 10, 'Banrural', NULL, NULL, 1, NULL, v_id);
        DBMS_OUTPUT.PUT_LINE('[FALLO] aceptó una transferencia sin referencia');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[OK] Transferencia sin referencia rechazada: ' || SQLERRM);
    END;
END;
/
