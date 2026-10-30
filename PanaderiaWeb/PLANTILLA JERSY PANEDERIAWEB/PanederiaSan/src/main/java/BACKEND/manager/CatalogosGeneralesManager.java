package BACKEND.manager;

import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import BACKEND.utils.Config;
import BACKEND.utils.ConnectionsPool;
import BACKEND.utils.jsonResult;
import javax.ws.rs.client.Client;
import javax.ws.rs.client.ClientBuilder;
import javax.ws.rs.client.WebTarget;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import oracle.jdbc.OracleTypes;

public class CatalogosGeneralesManager {
    String SCHEMA = new Config().getDBSchema();

   
    public List<Map<String, Object>> GetCategoriasProductos() throws Exception {
        List<Map<String, Object>> salida = new ArrayList<Map<String, Object>>();

        ConnectionsPool c = new ConnectionsPool();
        Connection conn = c.conectar();

        // Prepare a PL/SQL call
        CallableStatement call
                = conn.prepareCall("call " + SCHEMA + ".PKG_CATALOGOS.PROC_GET_CATEGORIAS_PRODUCTOS(?)");

        // Parametros
        call.registerOutParameter("p_cur_dataset", OracleTypes.CURSOR);
        call.execute();
        ResultSet rset = (ResultSet) call.getObject("p_cur_dataset");

        // Dump the cursor
        ResultSetMetaData meta = rset.getMetaData();

        while (rset.next()) {
            Map<String, Object> map = new HashMap<String, Object>();
            for (int i = 1; i <= meta.getColumnCount(); i++) {
                String key = meta.getColumnName(i).toString();
                String value = Objects.toString(rset.getString(key), "");
                map.put(key, value);
            }
            salida.add(map);
        }
        // Close all the resources
        rset.close();
        call.close();
        conn.close();

        return salida;
    }

   public List<Map<String, Object>> GetProductosCategoria(String id_categoria) throws Exception{
        List<Map<String, Object>> salida = new ArrayList<Map<String, Object>>();
       
        ConnectionsPool c=new ConnectionsPool();
        Connection conn=c.conectar();
               
         // Prepare a PL/SQL call
        CallableStatement call =
        conn.prepareCall ("call "+SCHEMA+".PKG_CATALOGOS.PROC_GET_ARTICULOS(?,?)");
        
        // Parametros
        call.setString("p_id_categoria", id_categoria);
        call.registerOutParameter ("p_cur_dataset", OracleTypes.CURSOR);
        call.execute ();
        ResultSet rset = (ResultSet)call.getObject ("p_cur_dataset");
        
        // Dump the cursor
        ResultSetMetaData meta = rset.getMetaData();
   
	    while (rset.next()) {
	    Map<String, Object> map = new HashMap<String, Object>();
	    for (int i = 1; i <= meta.getColumnCount(); i++) {
	        String key = meta.getColumnName(i).toString();
	        String value = Objects.toString(rset.getString(key), "");
	        map.put(key, value);
	    }     
	    salida.add(map);
	    }
    // Close all the resources
    rset.close();
    call.close();
    conn.close();
   
    return salida;
	}
}
