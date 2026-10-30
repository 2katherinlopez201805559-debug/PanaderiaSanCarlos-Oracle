package BACKEND.manager;

import BACKEND.model.Produccion;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

public class ProductoManager extends PanaderiaBaseManager {

    public List<Map<String, Object>> ObtenerProductos() throws Exception {
        return consultar(PKG_WEB, "SP_LISTAR_PRODUCTOS");
    }

    public List<Map<String, Object>> ObtenerReceta(int idProducto) throws Exception {
        return consultar(PKG_WEB, "SP_LISTAR_RECETA", idProducto);
    }

    /** Produce pan: descuenta insumos según la receta y suma al stock del pan. */
    public void ProducirPan(Produccion item) throws Exception {
        ejecutar(PKG_PANADERIA, "SP_PRODUCIR_PAN",
                item.ID_PRODUCTO, BigDecimal.valueOf(item.CANTIDAD));
    }
}
