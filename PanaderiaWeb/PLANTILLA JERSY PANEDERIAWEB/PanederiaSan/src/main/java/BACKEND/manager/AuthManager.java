package BACKEND.manager;

import BACKEND.utils.UsuarioSesion;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.Types;

public class AuthManager extends PanaderiaBaseManager {

    /** Valida usuario y contraseña en PKG_SEGURIDAD.SP_LOGIN (la clave se compara como hash SHA-256). */
    public UsuarioSesion Login(String usuario, String clave) throws Exception {
        try (Connection conn = abrirConexion();
             CallableStatement call = conn.prepareCall(llamada("PKG_SEGURIDAD", "SP_LOGIN", 7))) {
            call.setString(1, usuario);
            call.setString(2, clave);
            call.registerOutParameter(3, Types.NUMERIC);
            call.registerOutParameter(4, Types.VARCHAR);
            call.registerOutParameter(5, Types.VARCHAR);
            call.registerOutParameter(6, Types.NUMERIC);
            call.registerOutParameter(7, Types.VARCHAR);
            call.execute();

            int idSucursal = call.getInt(6);
            boolean sinSucursal = call.wasNull();
            return new UsuarioSesion(
                    call.getInt(3),
                    usuario.trim().toLowerCase(),
                    call.getString(4),
                    call.getString(5),
                    sinSucursal ? null : idSucursal);
        }
    }

    /** Nombre de la sucursal del usuario (para mostrarlo en pantalla). */
    public String NombreSucursal(Integer idSucursal) throws Exception {
        if (idSucursal == null) {
            return null;
        }
        for (java.util.Map<String, Object> s : consultar(PKG_WEB, "SP_LISTAR_SUCURSALES")) {
            if (idSucursal.toString().equals(String.valueOf(s.get("ID_SUCURSAL")))) {
                return String.valueOf(s.get("NOMBRE"));
            }
        }
        return null;
    }
}
