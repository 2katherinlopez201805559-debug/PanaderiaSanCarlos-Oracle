package BACKEND.manager;

import BACKEND.model.Pago;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.Types;
import java.util.List;
import java.util.Map;

/** Pagos de pedidos (PKG_PAGO). */
public class PagoManager extends PanaderiaBaseManager {

    private static final String PKG_PAGO = "PKG_PAGO";

    /** idSucursal null = todas (gerente). */
    public List<Map<String, Object>> ObtenerPagos(Integer idSucursal, String estado) throws Exception {
        return consultar(PKG_PAGO, "SP_LISTAR", idSucursal, estado);
    }

    /** Pedidos con total, crédito por devoluciones, pagado y saldo. */
    public List<Map<String, Object>> EstadoCuenta(Integer idSucursal) throws Exception {
        return consultar(PKG_PAGO, "SP_ESTADO_CUENTA", idSucursal);
    }

    /**
     * Registra el pago. idSucursal null = lo registra gerencia (queda CONFIRMADO);
     * con sucursal queda PENDIENTE hasta que gerencia lo revise. Devuelve el ID.
     */
    public int Registrar(Pago p, int idUsuario, Integer idSucursal) throws Exception {
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada(PKG_PAGO, "SP_REGISTRAR", 9))) {
            call.setInt(1, p.ID_PEDIDO);
            call.setString(2, p.METODO);
            call.setBigDecimal(3, BigDecimal.valueOf(p.MONTO));
            call.setString(4, p.BANCO);
            call.setString(5, p.REFERENCIA);
            call.setString(6, p.OBSERVACION);
            call.setInt(7, idUsuario);
            if (idSucursal == null) {
                call.setNull(8, Types.NUMERIC);
            } else {
                call.setInt(8, idSucursal);
            }
            call.registerOutParameter(9, Types.NUMERIC);
            call.execute();
            return call.getInt(9);
        }
    }

    /** Confirmar (true) o rechazar (false) un pago pendiente. */
    public void Resolver(int idPago, boolean confirmar, int idUsuario) throws Exception {
        ejecutar(PKG_PAGO, "SP_RESOLVER", idPago, confirmar ? "S" : "N", idUsuario);
    }
}
