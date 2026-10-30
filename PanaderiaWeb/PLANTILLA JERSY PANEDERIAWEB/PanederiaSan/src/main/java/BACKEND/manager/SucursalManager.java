package BACKEND.manager;

import java.util.List;
import java.util.Map;

public class SucursalManager extends PanaderiaBaseManager {

    public List<Map<String, Object>> ObtenerSucursales() throws Exception {
        return consultar(PKG_WEB, "SP_LISTAR_SUCURSALES");
    }
}
