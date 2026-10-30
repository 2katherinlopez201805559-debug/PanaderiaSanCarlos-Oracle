package BACKEND.manager;

import BACKEND.model.Pedido;
import BACKEND.model.PedidoDetalle;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.Date;
import java.sql.Types;
import java.util.List;
import java.util.Map;

public class PedidoManager extends PanaderiaBaseManager {

    public List<Map<String, Object>> ObtenerPedidos(Integer idSucursal, String estado) throws Exception {
        return consultar(PKG_WEB, "SP_LISTAR_PEDIDOS", idSucursal, estado);
    }

    public List<Map<String, Object>> ObtenerDetalle(int idPedido) throws Exception {
        return consultar(PKG_WEB, "SP_LISTAR_DETALLE_PEDIDO", idPedido);
    }

    /**
     * Registra el pedido completo (encabezado + panes) en UNA transacción
     * dentro de PKG_PANADERIA_WEB.SP_REGISTRAR_PEDIDO. Devuelve el ID creado.
     */
    public int RegistrarPedido(Pedido item) throws Exception {
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada(PKG_WEB, "SP_REGISTRAR_PEDIDO", 4))) {
            call.setInt(1, item.ID_SUCURSAL);
            Date fecha = convertirFecha(item.FECHA_ENTREGA);
            if (fecha == null) {
                call.setNull(2, Types.DATE);
            } else {
                call.setDate(2, fecha);
            }
            call.setString(3, armarDetalle(item.DETALLE));
            call.registerOutParameter(4, Types.NUMERIC);
            call.execute();
            return call.getInt(4);
        }
    }

    /** Sucursal dueña del pedido (para validar permisos). */
    public Integer SucursalDePedido(int idPedido) throws Exception {
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada("PKG_SEGURIDAD", "SP_SUCURSAL_DE_PEDIDO", 2))) {
            call.setInt(1, idPedido);
            call.registerOutParameter(2, Types.NUMERIC);
            call.execute();
            int id = call.getInt(2);
            return call.wasNull() ? null : id;
        }
    }

    public void Despachar(int idPedido) throws Exception {
        ejecutar(PKG_PANADERIA, "SP_DESPACHAR_PEDIDO", idPedido);
    }

    public void Entregar(int idPedido) throws Exception {
        ejecutar(PKG_PANADERIA, "SP_ENTREGAR_PEDIDO", idPedido);
    }

    public void Cancelar(int idPedido) throws Exception {
        ejecutar(PKG_PANADERIA, "SP_CANCELAR_PEDIDO", idPedido);
    }

    /** [ {3,20}, {2,10} ]  ->  "3:20;2:10" */
    private String armarDetalle(List<PedidoDetalle> detalle) {
        StringBuilder sb = new StringBuilder();
        for (PedidoDetalle d : detalle) {
            if (sb.length() > 0) {
                sb.append(';');
            }
            sb.append(d.ID_PRODUCTO).append(':')
              .append(BigDecimal.valueOf(d.CANTIDAD).stripTrailingZeros().toPlainString());
        }
        return sb.toString();
    }
}
