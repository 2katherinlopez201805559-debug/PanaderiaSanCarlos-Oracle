package BACKEND.manager;

import BACKEND.model.Devolucion;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.Types;
import java.util.List;
import java.util.Map;

public class DevolucionManager extends PanaderiaBaseManager {

    private static final String PKG_DEVOLUCION = "PKG_DEVOLUCION";

    /** idSucursal null = todas (gerente). */
    public List<Map<String, Object>> ObtenerDevoluciones(Integer idSucursal, String estado) throws Exception {
        return consultar(PKG_DEVOLUCION, "SP_LISTAR", idSucursal, estado);
    }

    /** Registra la devolución (una transacción en PKG_DEVOLUCION.SP_REGISTRAR). Devuelve el ID. */
    public int Registrar(Devolucion d, int idUsuario, Integer idSucursal) throws Exception {
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada(PKG_DEVOLUCION, "SP_REGISTRAR", 8))) {
            call.setInt(1, d.ID_PEDIDO);
            call.setInt(2, d.ID_PRODUCTO);
            call.setBigDecimal(3, BigDecimal.valueOf(d.CANTIDAD));
            call.setString(4, d.MOTIVO);
            call.setString(5, d.OBSERVACION);
            call.setInt(6, idUsuario);
            if (idSucursal == null) {
                call.setNull(7, Types.NUMERIC);
            } else {
                call.setInt(7, idSucursal);
            }
            call.registerOutParameter(8, Types.NUMERIC);
            call.execute();
            return call.getInt(8);
        }
    }

    /** Aprobar (true) o rechazar (false). Si se aprueba y el pan está bueno, regresa al inventario. */
    public void Resolver(int idDevolucion, boolean aprobar, int idUsuario) throws Exception {
        ejecutar(PKG_DEVOLUCION, "SP_RESOLVER", idDevolucion, aprobar ? "S" : "N", idUsuario);
    }
}
