USE proyecto_salud_2021;

-- Tabla integrada que puede exportarse desde MySQL Workbench a CSV.
SELECT provincia, anio, poblacion, medicos_ponderados_publicados, medicos_por_10000_aprox
FROM medicos_poblacion_2021 ORDER BY provincia;

-- Resultado de cada comprobación del ETL.
SELECT orden, control, observado, esperado, resultado
FROM revision_datos ORDER BY orden;

-- La tasa nacional se calcula con los totales de las provincias.
SELECT SUM(poblacion) AS poblacion_total,
       SUM(medicos_ponderados_publicados) AS medicos_total_publicado,
       ROUND(SUM(medicos_ponderados_publicados) * 10000.0 / SUM(poblacion), 2) AS tasa_nacional_aprox
FROM medicos_poblacion_2021;

-- Diagnóstico real de los datos cargados.
SELECT (SELECT COUNT(*) FROM medicos_originales) AS filas_medicos_originales,
       (SELECT COUNT(*) FROM medicos_por_provincia) AS filas_medicos_provinciales,
       (SELECT COUNT(*) FROM medicos_originales) - (SELECT COUNT(*) FROM medicos_por_provincia) AS filas_presentacion_excluidas,
       (SELECT COUNT(DISTINCT hoja) FROM poblacion_original) AS hojas_datos_poblacion,
       (SELECT COUNT(*) FROM poblacion_2021_preparada) AS filas_poblacion_2021_ambos_sexos;

-- Filas del CSV de presentación que se excluyen de la suma provincial.
SELECT m.registro_csv, m.provincia_original, m.cantidad_medicos_original
FROM medicos_con_nombres_uniformes m
LEFT JOIN (SELECT DISTINCT nombre_para_unir FROM poblacion_total_por_provincia) p
    ON m.nombre_para_unir = p.nombre_para_unir
WHERE p.nombre_para_unir IS NULL
ORDER BY m.registro_csv;
