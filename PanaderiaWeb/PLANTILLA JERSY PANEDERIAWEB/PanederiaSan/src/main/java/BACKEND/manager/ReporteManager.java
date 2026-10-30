package BACKEND.manager;

import java.util.List;
import java.util.Map;

public class ReporteManager extends PanaderiaBaseManager {

    /** Panes e insumos en o bajo su existencia mínima. */
    public List<Map<String, Object>> ObtenerAlertas() throws Exception {
        return consultar(PKG_WEB, "SP_LISTAR_ALERTAS");
    }

    /** Total pedido por pan (pedidos PENDIENTES) vs. stock: cuánto falta producir. */
    public List<Map<String, Object>> ObtenerResumenProduccion(String fechaEntrega) throws Exception {
        return consultar(PKG_WEB, "SP_RESUMEN_PRODUCCION", convertirFecha(fechaEntrega));
    }
}
