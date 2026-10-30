package BACKEND.utils;

import javax.ws.rs.core.Response;

/**
 * Respuestas HTTP uniformes para todos los controladores.
 *   200 -> datos o jsonResult OK
 *   400 -> regla de negocio (stock insuficiente, pedido ya despachado, etc.)
 *   500 -> error técnico (sin conexión, SQL mal escrito, etc.)
 */
public final class Respuesta {

    private Respuesta() {
    }

    public static Response ok(Object datos) {
        return Response.ok(datos).build();
    }

    public static Response ok(int id, String mensaje) {
        return Response.ok(new jsonResult(id, "OK", mensaje)).build();
    }

    public static Response validacion(String mensaje) {
        return Response.status(Response.Status.BAD_REQUEST)
                .entity(new jsonResult(-1, "ERROR", mensaje))
                .build();
    }

    public static Response error(Exception e) {
        // Permisos (401/403) lanzados por Acceso: se devuelven tal cual
        if (e instanceof javax.ws.rs.WebApplicationException) {
            return ((javax.ws.rs.WebApplicationException) e).getResponse();
        }
        if (e instanceof IllegalArgumentException) {
            return validacion(e.getMessage());
        }
        e.printStackTrace();
        Response.Status estado = DBUtils.esErrorDeNegocio(e)
                ? Response.Status.BAD_REQUEST
                : Response.Status.INTERNAL_SERVER_ERROR;
        return Response.status(estado)
                .entity(new jsonResult(-1, "ERROR", DBUtils.mensajeError(e)))
                .build();
    }
}
