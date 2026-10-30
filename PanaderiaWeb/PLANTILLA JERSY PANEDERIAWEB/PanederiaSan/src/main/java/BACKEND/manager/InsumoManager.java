package BACKEND.manager;

import BACKEND.model.CompraInsumo;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

public class InsumoManager extends PanaderiaBaseManager {

    public List<Map<String, Object>> ObtenerInsumos() throws Exception {
        return consultar(PKG_WEB, "SP_LISTAR_INSUMOS");
    }

    /** Registra una compra de materia prima (sube el stock del insumo). */
    public void RegistrarCompra(CompraInsumo item) throws Exception {
        ejecutar(PKG_PANADERIA, "SP_REGISTRAR_COMPRA_INSUMO",
                item.ID_INSUMO, BigDecimal.valueOf(item.CANTIDAD));
    }
}
