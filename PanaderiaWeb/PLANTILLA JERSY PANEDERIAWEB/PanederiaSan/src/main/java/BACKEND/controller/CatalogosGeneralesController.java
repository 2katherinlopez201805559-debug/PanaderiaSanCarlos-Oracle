package BACKEND.controller;

import javax.servlet.http.HttpServletRequest;
import javax.ws.rs.Consumes;
import javax.ws.rs.GET;
import javax.ws.rs.POST;
import javax.ws.rs.PUT;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.Produces;
import javax.ws.rs.core.Context;
import javax.ws.rs.core.Response;
import BACKEND.manager.CatalogosGeneralesManager;
import BACKEND.utils.jsonResult;

@Path("Catalogos")
public class CatalogosGeneralesController {

    CatalogosGeneralesManager manager = new CatalogosGeneralesManager();

    @GET
    @Path("/GetCategoriasProductos")
    @Produces("application/json")
    public Response GetCategoriasProductos() {
        try {
            return Response.ok(manager.GetCategoriasProductos()).build();
        } catch (Exception e) {
            e.printStackTrace();
            return Response.ok(new jsonResult(-1, "Error", e.getMessage())).build();
        }
    }

   
 @GET
    @Path("/Categoria/{id_categoria}/Productos")
    @Produces("application/json")
    public Response GetProductosCategoria(@PathParam("id_categoria")String id_categoria) {
        try {
            return Response.ok(manager.GetProductosCategoria(id_categoria)).build();
        } catch (Exception e) {
            e.printStackTrace();
            return Response.ok(new jsonResult(-1, "Error", e.getMessage())).build();
        }
    }

}
