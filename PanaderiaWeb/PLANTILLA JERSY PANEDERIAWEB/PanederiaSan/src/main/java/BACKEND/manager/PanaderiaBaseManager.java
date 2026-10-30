package BACKEND.manager;

import BACKEND.utils.Config;
import BACKEND.utils.ConnectionsPool;
import BACKEND.utils.DBUtils;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import oracle.jdbc.OracleTypes;

/**
 * Clase base de todos los managers de la panadería.
 * Centraliza: apertura/cierre de conexión, armado de la llamada al
 * procedimiento y lectura de cursores. Así cada manager solo indica
 * QUÉ procedimiento llamar y con qué parámetros.
 *
 * El control transaccional (COMMIT / ROLLBACK) lo hace cada
 * procedimiento dentro de los paquetes PL/SQL.
 */
public abstract class PanaderiaBaseManager {

    protected static final String PKG_PANADERIA = "PKG_PANADERIA";
    protected static final String PKG_WEB = "PKG_PANADERIA_WEB";

    private final String prefijoEsquema;

    protected PanaderiaBaseManager() {
        String esquema = new Config().getDBSchema();
        this.prefijoEsquema = (esquema == null || esquema.trim().isEmpty()) ? "" : esquema.trim() + ".";
    }

    /** Abre una conexión usando el pool de la plantilla. */
    protected Connection abrirConexion() throws SQLException {
        return new ConnectionsPool().conectar();
    }

    /** Arma "{call ESQUEMA.PAQUETE.PROCEDIMIENTO(?,?,...)}". */
    protected String llamada(String paquete, String procedimiento, int totalParametros) {
        StringBuilder sb = new StringBuilder("{call ");
        sb.append(prefijoEsquema).append(paquete).append('.').append(procedimiento).append('(');
        for (int i = 0; i < totalParametros; i++) {
            sb.append(i == 0 ? "?" : ",?");
        }
        return sb.append(")}").toString();
    }

    /** Asigna parámetros de entrada en orden (null se envía como NULL). */
    protected void asignarParametros(CallableStatement call, Object... parametros) throws SQLException {
        for (int i = 0; i < parametros.length; i++) {
            if (parametros[i] == null) {
                call.setNull(i + 1, Types.VARCHAR);
            } else {
                call.setObject(i + 1, parametros[i]);
            }
        }
    }

    /**
     * Ejecuta un procedimiento cuyo ÚLTIMO parámetro es un SYS_REFCURSOR
     * y devuelve las filas como lista.
     */
    protected List<Map<String, Object>> consultar(String paquete, String procedimiento, Object... parametros)
            throws SQLException {
        int posCursor = parametros.length + 1;
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada(paquete, procedimiento, posCursor))) {
            asignarParametros(call, parametros);
            call.registerOutParameter(posCursor, OracleTypes.CURSOR);
            call.execute();
            try (ResultSet rs = (ResultSet) call.getObject(posCursor)) {
                return DBUtils.cursorALista(rs);
            }
        }
    }

    /** Ejecuta un procedimiento que solo recibe parámetros de entrada. */
    protected void ejecutar(String paquete, String procedimiento, Object... parametros) throws SQLException {
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada(paquete, procedimiento, parametros.length))) {
            asignarParametros(call, parametros);
            call.execute();
        }
    }

    /** "2026-10-02" -> java.sql.Date ; vacío -> null */
    protected java.sql.Date convertirFecha(String texto) {
        if (texto == null || texto.trim().isEmpty()) {
            return null;
        }
        try {
            return java.sql.Date.valueOf(texto.trim());
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("La fecha debe tener formato AAAA-MM-DD.");
        }
    }
}
