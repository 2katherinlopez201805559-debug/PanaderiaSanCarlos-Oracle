package BACKEND.utils;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Utilidades reutilizables para trabajar con la base de datos Oracle.
 */
public final class DBUtils {

    private DBUtils() {
    }

    /**
     * Convierte un cursor (ResultSet) en una lista de filas.
     * Cada fila es un mapa COLUMNA -> valor (números como número, fechas como texto).
     */
    public static List<Map<String, Object>> cursorALista(ResultSet rs) throws SQLException {
        List<Map<String, Object>> salida = new ArrayList<Map<String, Object>>();
        ResultSetMetaData meta = rs.getMetaData();
        int columnas = meta.getColumnCount();
        SimpleDateFormat formato = new SimpleDateFormat("yyyy-MM-dd HH:mm");

        while (rs.next()) {
            Map<String, Object> fila = new LinkedHashMap<String, Object>();
            for (int i = 1; i <= columnas; i++) {
                String columna = meta.getColumnLabel(i);
                Object valor = rs.getObject(i);
                if (valor instanceof Number) {
                    valor = new BigDecimal(valor.toString());
                } else if (valor instanceof java.util.Date) {
                    valor = formato.format((java.util.Date) valor);
                } else if (valor != null) {
                    valor = valor.toString();
                }
                fila.put(columna, valor);
            }
            salida.add(fila);
        }
        return salida;
    }

    /**
     * true si el error viene de RAISE_APPLICATION_ERROR (-20000 a -20999),
     * es decir, una regla de negocio del paquete y no una falla técnica.
     */
    public static boolean esErrorDeNegocio(Throwable e) {
        SQLException sql = buscarSQLException(e);
        return sql != null && sql.getErrorCode() >= 20000 && sql.getErrorCode() <= 20999;
    }

    /**
     * Devuelve un mensaje limpio para mostrar al usuario.
     * "ORA-20001: Stock insuficiente...\nORA-06512: ..." -> "Stock insuficiente..."
     */
    public static String mensajeError(Throwable e) {
        SQLException sql = buscarSQLException(e);
        String mensaje = (sql != null) ? sql.getMessage() : e.getMessage();
        if (mensaje == null) {
            return "Error inesperado.";
        }
        String[] lineas = mensaje.split("\n");
        if (esErrorDeNegocio(e)) {
            return lineas[0].trim().replaceFirst("^ORA-\\d{5}:\\s*", "");
        }
        // Error técnico: se conservan las líneas útiles (ORA-06550 + PLS-xxxxx),
        // se omiten las de pila (ORA-06512).
        StringBuilder sb = new StringBuilder();
        for (String linea : lineas) {
            String l = linea.trim();
            if (l.isEmpty() || l.startsWith("ORA-06512")) {
                continue;
            }
            if (sb.length() > 0) {
                sb.append(' ');
            }
            sb.append(l);
        }
        return sb.toString();
    }

    private static SQLException buscarSQLException(Throwable e) {
        Throwable actual = e;
        while (actual != null) {
            if (actual instanceof SQLException) {
                return (SQLException) actual;
            }
            actual = actual.getCause();
        }
        return null;
    }
}
