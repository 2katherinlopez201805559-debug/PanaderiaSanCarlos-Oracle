package BACKEND.model;

import BACKEND.utils.Item;
import java.util.List;

public class Departamento extends Item{
	public String ID_UBICACION_GEOGRAFICA;
	public String ID_UBICACION_GEOGRARAFICA_PADRE;
	public String NOMBRE;
        public List<Municipio> MUNICIPIOS;
}
