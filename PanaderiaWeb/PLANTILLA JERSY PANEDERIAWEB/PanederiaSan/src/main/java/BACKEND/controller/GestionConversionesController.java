package BACKEND.controller;

import javax.servlet.http.HttpServletRequest;
import javax.ws.rs.Consumes;
import javax.ws.rs.GET;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.Produces;
import javax.ws.rs.core.Context;
import javax.ws.rs.core.Response;
import BACKEND.manager.EjemploManager;
import BACKEND.manager.GestionConversionesManager;
import BACKEND.model.Ejemplo;
import BACKEND.model.Sucursal;
import BACKEND.utils.jsonResult;

@Path("Convertidor")
public class GestionConversionesController {
	GestionConversionesManager manager = new GestionConversionesManager();
	
          @GET	
    @Path("/fecha/{fecha}/monto/{monto}/tipo/{tipo}/Convertir")
    @Produces("application/json")
    public Response ConvertirMoneda(@PathParam("fecha")String fecha,@PathParam("monto")String monto,@PathParam("tipo")String tipo) {
		try {
			return Response.ok(manager.ConvertirMoneda(fecha,monto,tipo)).build();
		} catch (Exception e) {
			e.printStackTrace(); 
			return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
		}
    }
    
    @GET
    @Path("/ObtenerCatalogoEjemplo")
    @Produces("application/json")
    public Response ObtenerCatalogoEjemplo() {
		try {
			return Response.ok(manager.ObtenerCatalogoEjemplo()).build();
		} catch (Exception e) {
			e.printStackTrace(); 
			return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
		}
    }
	
      @GET	
    @Path("/ObtenerSucursales")
    @Produces("application/json")
    public Response ObtenerSucursales() {
		try {
			return Response.ok(manager.ObtenerSucursales()).build();
		} catch (Exception e) {
			e.printStackTrace(); 
			return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
		}
    }
    
	@POST

	@Path("/AgregarEjemplo")
	@Consumes("application/json")
	@Produces("application/json")
	public Response insUsuario(@Context HttpServletRequest req,Ejemplo item) {	
		try {
			item.IP=req.getRemoteAddr();
			return Response.ok(manager.AgregarEjemplo(item)).build();
		} catch (Exception e) {
			e.printStackTrace(); 
			return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
		}
	}
        
        @POST

	@Path("/AgregarSucursal")
	@Consumes("application/json")
	@Produces("application/json")
	public Response AgregarSucursal(@Context HttpServletRequest req,Sucursal item) {	
		try {
			item.IP=req.getRemoteAddr();
			return Response.ok(manager.AgregarSucursal(item)).build();
		} catch (Exception e) {
			e.printStackTrace(); 
			return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
		}
	}

	/*@POST
    @Path("/AgregarEjemploTransaccional")
    @Consumes("application/json")
    @Produces("application/json;charset=UTF-8")
    public Response AgregarEjemploTransaccional(@Context HttpServletRequest req, Departamento item) {  
            try {
                    return Response.ok(manager.AgregarEjemploTransaccional(item)).build();
            } catch (Exception e) {
                    e.printStackTrace();
                    return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
            }
    }*/
	
	@GET
	
    @Path("/{id_ejemplo}/ObtenerEjemplo")
    @Produces("application/json")
    public Response ObtenerEjemplo(@PathParam("id_ejemplo")String id_ejemplo) {
		try {
			return Response.ok(manager.ObtenerEjemplo(id_ejemplo)).build();
		} catch (Exception e) {
			e.printStackTrace(); 
			return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
		}
    }
	

       @GET	
    @Path("/ObtenerMunicipiosDepto/{id_ubicacion_geografica}")
    @Produces("application/json")
    public Response ObtenerMunicipiosDepto(@PathParam("id_ubicacion_geografica")String id_ubicacion_geografica) {
		try {
			return Response.ok(manager.ObtenerMunicipiosDepto(id_ubicacion_geografica)).build();
		} catch (Exception e) {
			e.printStackTrace(); 
			return Response.ok(new jsonResult(-1,"Error",e.getMessage())).build();
		}
    }
    
}
