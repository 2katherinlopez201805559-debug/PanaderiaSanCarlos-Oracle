package BACKEND.manager;

import BACKEND.model.LineaReceta;
import BACKEND.model.NuevoPan;
import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.Types;
import java.util.List;

/** Panes nuevos y recetas (PKG_CATALOGO). Solo gerencia. */
public class CatalogoManager extends PanaderiaBaseManager {

    private static final String PKG_CATALOGO = "PKG_CATALOGO";

    /** Crea el pan y toda su receta en UNA transacción. Devuelve el ID del pan. */
    public int CrearPan(NuevoPan p) throws Exception {
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada(PKG_CATALOGO, "SP_CREAR_PAN", 6))) {
            call.setString(1, p.NOMBRE.trim());
            call.setString(2, p.UNIDAD_MEDIDA == null || p.UNIDAD_MEDIDA.trim().isEmpty() ? "unidad" : p.UNIDAD_MEDIDA.trim());
            call.setBigDecimal(3, BigDecimal.valueOf(p.PRECIO));
            call.setBigDecimal(4, BigDecimal.valueOf(p.STOCK_MINIMO));
            call.setString(5, armarReceta(p.RECETA));
            call.registerOutParameter(6, Types.NUMERIC);
            call.execute();
            return call.getInt(6);
        }
    }

    /** Reemplaza la receta completa del pan. */
    public void GuardarReceta(int idProducto, List<LineaReceta> receta) throws Exception {
        ejecutar(PKG_CATALOGO, "SP_GUARDAR_RECETA", idProducto, armarReceta(receta));
    }

    /** Cambia precio, existencia mínima y estado (ACTIVO / INACTIVO). */
    public void ActualizarPan(int idProducto, NuevoPan p) throws Exception {
        ejecutar(PKG_CATALOGO, "SP_ACTUALIZAR_PAN", idProducto,
                BigDecimal.valueOf(p.PRECIO), BigDecimal.valueOf(p.STOCK_MINIMO), p.ESTADO);
    }

    /** [{1, 0.35}, {7, 0.008}]  ->  "1:0.35;7:0.008" */
    private String armarReceta(List<LineaReceta> receta) {
        StringBuilder sb = new StringBuilder();
        for (LineaReceta l : receta) {
            if (sb.length() > 0) {
                sb.append(';');
            }
            sb.append(l.ID_INSUMO).append(':')
              .append(BigDecimal.valueOf(l.CANTIDAD).stripTrailingZeros().toPlainString());
        }
        return sb.toString();
    }
}
