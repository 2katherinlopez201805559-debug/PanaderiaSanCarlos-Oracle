-- =====================================================================
--  PANADERÍA SAN CARLOS - PAQUETE PARA EL SITIO WEB (PKG_PANADERIA_WEB)
--  Ejecutar DESPUÉS de panaderia_completo.sql, con F5 en SQL Developer.
--
--  Contiene:
--   * Consultas (cursores) que usa el backend para listar datos.
--   * SP_REGISTRAR_PEDIDO: crea un pedido COMPLETO (encabezado + todos
--     sus panes) en UNA sola transacción. Si un pan falla, no se guarda
--     nada (ROLLBACK).
--
--  Códigos de error nuevos:
--   -20010 formato de detalle inválido
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;

CREATE OR REPLACE PACKAGE PKG_PANADERIA_WEB AS
    -- Consultas
    PROCEDURE SP_LISTAR_SUCURSALES(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE SP_LISTAR_PRODUCTOS(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE SP_LISTAR_INSUMOS(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE SP_LISTAR_RECETA(p_id_producto IN NUMBER, p_cursor OUT SYS_REFCURSOR);
    PROCEDURE SP_LISTAR_PEDIDOS(p_id_sucursal IN NUMBER, p_estado IN VARCHAR2, p_cursor OUT SYS_REFCURSOR);
    PROCEDURE SP_LISTAR_DETALLE_PEDIDO(p_id_pedido IN NUMBER, p_cursor OUT SYS_REFCURSOR);
    PROCEDURE SP_LISTAR_ALERTAS(p_cursor OUT SYS_REFCURSOR);
    PROCEDURE SP_RESUMEN_PRODUCCION(p_fecha_entrega IN DATE, p_cursor OUT SYS_REFCURSOR);

    -- Transacción completa de un pedido.
    -- p_detalle: 'ID_PRODUCTO:CANTIDAD;ID_PRODUCTO:CANTIDAD'  ej. '3:20;2:10'
    PROCEDURE SP_REGISTRAR_PEDIDO(p_id_sucursal   IN  NUMBER,
                                  p_fecha_entrega IN  DATE,
                                  p_detalle       IN  VARCHAR2,
                                  p_id_pedido     OUT NUMBER);
END PKG_PANADERIA_WEB;
/

CREATE OR REPLACE PACKAGE BODY PKG_PANADERIA_WEB AS

    -- ------------------------- CONSULTAS -------------------------
    PROCEDURE SP_LISTAR_SUCURSALES(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT ID_SUCURSAL, NOMBRE, DIRECCION, TELEFONO, ESTADO
            FROM SUCURSAL
            ORDER BY ID_SUCURSAL;
    END SP_LISTAR_SUCURSALES;

    PROCEDURE SP_LISTAR_PRODUCTOS(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT ID_PRODUCTO, NOMBRE, UNIDAD_MEDIDA, PRECIO, STOCK_ACTUAL, STOCK_MINIMO, ESTADO,
                   CASE WHEN STOCK_ACTUAL <= STOCK_MINIMO THEN 'S' ELSE 'N' END AS ALERTA
            FROM PRODUCTO
            ORDER BY ID_PRODUCTO;
    END SP_LISTAR_PRODUCTOS;

    PROCEDURE SP_LISTAR_INSUMOS(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT ID_INSUMO, NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO, ESTADO,
                   CASE WHEN STOCK_ACTUAL <= STOCK_MINIMO THEN 'S' ELSE 'N' END AS ALERTA
            FROM INSUMO
            ORDER BY ID_INSUMO;
    END SP_LISTAR_INSUMOS;

    PROCEDURE SP_LISTAR_RECETA(p_id_producto IN NUMBER, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT r.ID_INSUMO, i.NOMBRE AS INSUMO, r.CANTIDAD, i.UNIDAD_MEDIDA
            FROM RECETA_DETALLE r
            JOIN INSUMO i ON i.ID_INSUMO = r.ID_INSUMO
            WHERE r.ID_PRODUCTO = p_id_producto
            ORDER BY i.ID_INSUMO;
    END SP_LISTAR_RECETA;

    PROCEDURE SP_LISTAR_PEDIDOS(p_id_sucursal IN NUMBER, p_estado IN VARCHAR2, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT p.ID_PEDIDO, p.ID_SUCURSAL, s.NOMBRE AS SUCURSAL,
                   TO_CHAR(p.FECHA_PEDIDO,  'YYYY-MM-DD HH24:MI') AS FECHA_PEDIDO,
                   TO_CHAR(p.FECHA_ENTREGA, 'YYYY-MM-DD')        AS FECHA_ENTREGA,
                   p.ESTADO, p.TOTAL
            FROM PEDIDO p
            JOIN SUCURSAL s ON s.ID_SUCURSAL = p.ID_SUCURSAL
            WHERE (p_id_sucursal IS NULL OR p.ID_SUCURSAL = p_id_sucursal)
              AND (p_estado      IS NULL OR p.ESTADO      = p_estado)
            ORDER BY p.ID_PEDIDO DESC;
    END SP_LISTAR_PEDIDOS;

    PROCEDURE SP_LISTAR_DETALLE_PEDIDO(p_id_pedido IN NUMBER, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT d.ID_PEDIDO_DETALLE, d.ID_PRODUCTO, pr.NOMBRE AS PRODUCTO,
                   d.CANTIDAD, d.PRECIO_UNITARIO, d.SUBTOTAL
            FROM PEDIDO_DETALLE d
            JOIN PRODUCTO pr ON pr.ID_PRODUCTO = d.ID_PRODUCTO
            WHERE d.ID_PEDIDO = p_id_pedido
            ORDER BY d.ID_PEDIDO_DETALLE;
    END SP_LISTAR_DETALLE_PEDIDO;

    PROCEDURE SP_LISTAR_ALERTAS(p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT TIPO, ID, NOMBRE, UNIDAD_MEDIDA, STOCK_ACTUAL, STOCK_MINIMO
            FROM V_ALERTA_STOCK
            ORDER BY TIPO, NOMBRE;
    END SP_LISTAR_ALERTAS;

    -- Cuánto pan piden las sucursales (pedidos PENDIENTES) vs. cuánto hay.
    -- Si p_fecha_entrega es NULL toma todos los pendientes.
    PROCEDURE SP_RESUMEN_PRODUCCION(p_fecha_entrega IN DATE, p_cursor OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_cursor FOR
            SELECT pr.ID_PRODUCTO, pr.NOMBRE,
                   NVL(x.CANTIDAD, 0)                               AS TOTAL_PEDIDO,
                   pr.STOCK_ACTUAL,
                   GREATEST(NVL(x.CANTIDAD, 0) - pr.STOCK_ACTUAL, 0) AS FALTA_PRODUCIR
            FROM PRODUCTO pr
            LEFT JOIN (
                SELECT d.ID_PRODUCTO, SUM(d.CANTIDAD) AS CANTIDAD
                FROM PEDIDO_DETALLE d
                JOIN PEDIDO p ON p.ID_PEDIDO = d.ID_PEDIDO
                WHERE p.ESTADO = 'PENDIENTE'
                  AND (p_fecha_entrega IS NULL OR TRUNC(p.FECHA_ENTREGA) = TRUNC(p_fecha_entrega))
                GROUP BY d.ID_PRODUCTO
            ) x ON x.ID_PRODUCTO = pr.ID_PRODUCTO
            WHERE pr.ESTADO = 'ACTIVO'
            ORDER BY pr.ID_PRODUCTO;
    END SP_RESUMEN_PRODUCCION;


    -- ------------------- PEDIDO COMPLETO (1 transacción) -------------------
    PROCEDURE SP_REGISTRAR_PEDIDO(p_id_sucursal   IN  NUMBER,
                                  p_fecha_entrega IN  DATE,
                                  p_detalle       IN  VARCHAR2,
                                  p_id_pedido     OUT NUMBER) IS
        v_item     VARCHAR2(200);
        v_pos      PLS_INTEGER;
        v_id_prod  NUMBER;
        v_cant     NUMBER;
        v_precio   PRODUCTO.PRECIO%TYPE;
        v_total    NUMBER := 0;
        v_lineas   PLS_INTEGER := 0;
        v_existe   NUMBER;
        i          PLS_INTEGER := 1;
    BEGIN
        -- 1. Validar sucursal y que venga detalle
        SELECT COUNT(*) INTO v_existe FROM SUCURSAL
        WHERE ID_SUCURSAL = p_id_sucursal AND ESTADO = 'ACTIVO';
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20007, 'La sucursal ' || p_id_sucursal || ' no existe o está inactiva.');
        END IF;

        IF TRIM(p_detalle) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20008, 'El pedido no tiene productos.');
        END IF;

        IF p_fecha_entrega IS NOT NULL AND TRUNC(p_fecha_entrega) < TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(-20010, 'La fecha de entrega no puede ser anterior a hoy.');
        END IF;

        -- 2. Encabezado
        INSERT INTO PEDIDO (ID_SUCURSAL, FECHA_ENTREGA, ESTADO, TOTAL)
        VALUES (p_id_sucursal, NVL(TRUNC(p_fecha_entrega), TRUNC(SYSDATE) + 1), 'PENDIENTE', 0)
        RETURNING ID_PEDIDO INTO p_id_pedido;

        -- 3. Recorrer cada 'ID:CANTIDAD'
        LOOP
            v_item := TRIM(REGEXP_SUBSTR(p_detalle, '[^;]+', 1, i));
            EXIT WHEN v_item IS NULL;

            v_pos := INSTR(v_item, ':');
            IF v_pos = 0 THEN
                RAISE_APPLICATION_ERROR(-20010, 'Formato inválido en "' || v_item || '". Use ID_PRODUCTO:CANTIDAD.');
            END IF;

            BEGIN
                v_id_prod := TO_NUMBER(TRIM(SUBSTR(v_item, 1, v_pos - 1)));
                v_cant    := TO_NUMBER(TRIM(SUBSTR(v_item, v_pos + 1)),
                                       '999999990D999', 'NLS_NUMERIC_CHARACTERS=''.,''');
            EXCEPTION
                WHEN VALUE_ERROR OR INVALID_NUMBER THEN
                    RAISE_APPLICATION_ERROR(-20010, 'Número inválido en "' || v_item || '".');
            END;

            IF v_cant IS NULL OR v_cant <= 0 THEN
                RAISE_APPLICATION_ERROR(-20005, 'La cantidad debe ser mayor que 0.');
            END IF;

            BEGIN
                SELECT PRECIO INTO v_precio FROM PRODUCTO
                WHERE ID_PRODUCTO = v_id_prod AND ESTADO = 'ACTIVO';
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(-20002, 'El producto ' || v_id_prod || ' no existe o está inactivo.');
            END;

            INSERT INTO PEDIDO_DETALLE (ID_PEDIDO, ID_PRODUCTO, CANTIDAD, PRECIO_UNITARIO)
            VALUES (p_id_pedido, v_id_prod, v_cant, v_precio);

            v_total  := v_total + (v_cant * v_precio);
            v_lineas := v_lineas + 1;
            i := i + 1;
        END LOOP;

        IF v_lineas = 0 THEN
            RAISE_APPLICATION_ERROR(-20008, 'El pedido no tiene productos.');
        END IF;

        -- 4. Total y confirmación (todo o nada)
        UPDATE PEDIDO SET TOTAL = v_total WHERE ID_PEDIDO = p_id_pedido;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_id_pedido := NULL;
            RAISE;
    END SP_REGISTRAR_PEDIDO;

END PKG_PANADERIA_WEB;
/

-- Verificar que compiló (VALID y sin filas de error)
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS FROM USER_OBJECTS WHERE OBJECT_NAME = 'PKG_PANADERIA_WEB';
SELECT LINE, POSITION, TEXT FROM USER_ERRORS WHERE NAME = 'PKG_PANADERIA_WEB' ORDER BY SEQUENCE;


-- =====================================================================
-- PRUEBA RÁPIDA
-- =====================================================================
DECLARE
    v_id     NUMBER;
    v_cur    SYS_REFCURSOR;
    v_nombre VARCHAR2(150);
    v_total  NUMBER;
    v_falta  NUMBER;
    v_idp    NUMBER;
    v_stock  NUMBER;
    v_central NUMBER;
    v_pedidos_antes NUMBER;
    v_pedidos_despues NUMBER;
BEGIN
    SELECT ID_SUCURSAL INTO v_central FROM SUCURSAL WHERE NOMBRE = 'CENTRAL';

    -- 1. Pedido correcto: 20 Francés (id 3) + 10 Especial (id 2)
    PKG_PANADERIA_WEB.SP_REGISTRAR_PEDIDO(v_central, TRUNC(SYSDATE) + 1, '3:20;2:10', v_id);
    DBMS_OUTPUT.PUT_LINE('[OK] Pedido completo creado con ID ' || v_id);

    -- 2. Pedido con un producto inexistente: NO debe guardarse nada
    SELECT COUNT(*) INTO v_pedidos_antes FROM PEDIDO;
    BEGIN
        PKG_PANADERIA_WEB.SP_REGISTRAR_PEDIDO(v_central, TRUNC(SYSDATE) + 1, '3:5;9999:1', v_id);
        DBMS_OUTPUT.PUT_LINE('[FALLO] debió rechazar el producto 9999');
    EXCEPTION WHEN OTHERS THEN
        SELECT COUNT(*) INTO v_pedidos_despues FROM PEDIDO;
        IF v_pedidos_antes = v_pedidos_despues THEN
            DBMS_OUTPUT.PUT_LINE('[OK] Rechazado y sin guardar nada: ' || SQLERRM);
        ELSE
            DBMS_OUTPUT.PUT_LINE('[FALLO] quedó un pedido a medias');
        END IF;
    END;

    -- 3. Resumen de producción para mañana
    PKG_PANADERIA_WEB.SP_RESUMEN_PRODUCCION(TRUNC(SYSDATE) + 1, v_cur);
    DBMS_OUTPUT.PUT_LINE('--- Resumen de producción para mañana ---');
    LOOP
        FETCH v_cur INTO v_idp, v_nombre, v_total, v_stock, v_falta;
        EXIT WHEN v_cur%NOTFOUND;
        IF v_total > 0 THEN
            DBMS_OUTPUT.PUT_LINE(RPAD(v_nombre, 14) || ' pedido=' || v_total || '  stock=' || v_stock || '  falta=' || v_falta);
        END IF;
    END LOOP;
    CLOSE v_cur;
END;
/
