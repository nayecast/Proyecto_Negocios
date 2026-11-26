-- Limpieza, validación, integración y carga realizadas por MySQL.
USE proyecto_salud_2021;
DROP PROCEDURE IF EXISTS preparar_datos_salud;
-- Estos signos permiten agrupar todas las instrucciones del proceso.
DELIMITER $$
CREATE PROCEDURE preparar_datos_salud()
BEGIN
    DECLARE bloqueo INT DEFAULT 0;
    DECLARE total_medicos BIGINT;
    DECLARE modo_seguro_anterior INT;
    -- Si aparece un error, deshacer los cambios y mostrar el mensaje.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET SESSION SQL_SAFE_UPDATES = modo_seguro_anterior;
        IF bloqueo = 1 THEN
            DO RELEASE_LOCK('proyecto_salud_2021_etl');
        END IF;
        RESIGNAL;
    END;

    SET modo_seguro_anterior = @@SESSION.sql_safe_updates;
    -- Evitar que dos ejecuciones cambien los resultados al mismo tiempo.
    SELECT GET_LOCK('proyecto_salud_2021_etl', 10) INTO bloqueo;
    IF bloqueo IS NULL OR bloqueo <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Otra ejecución está utilizando el ETL.';
    END IF;

    -- Los resultados se guardarán juntos al terminar todas las comprobaciones.
    START TRANSACTION;
    -- Permitir la actualización completa de las tablas de este proceso.
    SET SESSION SQL_SAFE_UPDATES = 0;
    DELETE FROM revision_datos;

    INSERT INTO revision_datos
    SELECT 1, 'Registros médicos importados completos', CAST(COUNT(*) AS CHAR),
           CAST(MAX(f.cantidad_registros) AS CHAR),
           IF(COUNT(*) = MAX(f.cantidad_registros), 'CORRECTO', 'ERROR')
    FROM medicos_originales CROSS JOIN origen_archivos f WHERE f.fuente = 'medicos';

    INSERT INTO revision_datos
    SELECT 2, 'Registros de población importados completos', CAST(COUNT(*) AS CHAR),
           CAST(MAX(f.cantidad_registros) AS CHAR),
           IF(COUNT(*) = MAX(f.cantidad_registros), 'CORRECTO', 'ERROR')
    FROM poblacion_original CROSS JOIN origen_archivos f WHERE f.fuente = 'poblacion';

    INSERT INTO revision_datos
    SELECT 3, 'Totales poblacionales únicos para las 24 provincias',
           CONCAT(COUNT(*), ' filas / ', COUNT(DISTINCT nombre_para_unir), ' provincias'),
           '24 filas / 24 provincias',
           IF(COUNT(*) = 24 AND COUNT(DISTINCT nombre_para_unir) = 24, 'CORRECTO', 'ERROR')
    FROM poblacion_total_por_provincia;

    INSERT INTO revision_datos
    SELECT 4, 'Cantidades poblacionales válidas en total y grupos de edad',
           CAST(COALESCE(SUM(cantidad_sin_separadores IS NULL OR cantidad_sin_separadores NOT REGEXP '^[0-9]+$'), 0) AS CHAR),
           '0 valores inválidos',
           IF(COALESCE(SUM(cantidad_sin_separadores IS NULL OR cantidad_sin_separadores NOT REGEXP '^[0-9]+$'), 0) = 0, 'CORRECTO', 'ERROR')
    FROM poblacion_2021_preparada;

    INSERT INTO revision_datos
    SELECT 5, 'Correspondencia médica única para las 24 provincias',
           CONCAT(COUNT(*), ' filas / ', COUNT(DISTINCT nombre_para_unir), ' provincias'),
           '24 filas / 24 provincias',
           IF(COUNT(*) = 24 AND COUNT(DISTINCT nombre_para_unir) = 24, 'CORRECTO', 'ERROR')
    FROM medicos_por_provincia;

    INSERT INTO revision_datos
    SELECT 6, 'Cantidades médicas completas y numéricas',
           CAST(COALESCE(SUM(cantidad_sin_separadores IS NULL OR cantidad_sin_separadores NOT REGEXP '^[0-9]+$'), 0) AS CHAR),
           '0 valores inválidos',
           IF(COALESCE(SUM(cantidad_sin_separadores IS NULL OR cantidad_sin_separadores NOT REGEXP '^[0-9]+$'), 0) = 0, 'CORRECTO', 'ERROR')
    FROM medicos_por_provincia;

    IF EXISTS (SELECT 1 FROM revision_datos WHERE resultado = 'ERROR') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Datos incompletos, inválidos o claves repetidas. Se conserva el resultado anterior.';
    END IF;

    INSERT INTO revision_datos
    SELECT 7, 'Total poblacional igual a suma de 21 grupos por provincia',
           CAST(COUNT(*) AS CHAR), '0 provincias con diferencia', IF(COUNT(*) = 0, 'CORRECTO', 'ERROR')
    FROM (
        SELECT nombre_para_unir
        FROM poblacion_2021_preparada
        GROUP BY nombre_para_unir
        HAVING SUM(grupo_edad_uniforme <> 'TOTAL') <> 21
            OR MAX(CASE WHEN grupo_edad_uniforme = 'TOTAL' THEN CAST(cantidad_sin_separadores AS UNSIGNED) END)
               <> SUM(CASE WHEN grupo_edad_uniforme <> 'TOTAL' THEN CAST(cantidad_sin_separadores AS UNSIGNED) ELSE 0 END)
    ) AS diferencias;

    INSERT INTO revision_datos
    SELECT 8, 'Población positiva en todas las provincias',
           CAST(COALESCE(SUM(CAST(cantidad_sin_separadores AS UNSIGNED) <= 0), 0) AS CHAR),
           '0 provincias con población no positiva',
           IF(COALESCE(SUM(CAST(cantidad_sin_separadores AS UNSIGNED) <= 0), 0) = 0, 'CORRECTO', 'ERROR')
    FROM poblacion_total_por_provincia;

    SELECT CAST(cantidad_sin_separadores AS UNSIGNED) INTO total_medicos
    FROM medicos_con_nombres_uniformes WHERE nombre_para_unir = 'TOTAL NACIONAL';

    INSERT INTO revision_datos
    SELECT 9, 'Suma médica provincial compatible con total nacional publicado',
           CAST(SUM(CAST(cantidad_sin_separadores AS UNSIGNED)) - total_medicos AS CHAR),
           'Diferencia absoluta de hasta 12 por redondeo',
           IF(total_medicos IS NOT NULL AND ABS(SUM(CAST(cantidad_sin_separadores AS UNSIGNED)) - total_medicos) <= 12, 'CORRECTO', 'ERROR')
    FROM medicos_por_provincia;

    IF EXISTS (SELECT 1 FROM revision_datos WHERE resultado = 'ERROR') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falló la comprobación de totales. Se conserva el resultado anterior.';
    END IF;

    -- DELETE e INSERT forman una sola transacción. Repetir evita duplicados.
    DELETE FROM medicos_poblacion_2021;
    INSERT INTO medicos_poblacion_2021
        (provincia, anio, poblacion, medicos_ponderados_publicados, medicos_por_10000_aprox)
    SELECT TRIM(p.provincia_original), 2021,
           CAST(p.cantidad_sin_separadores AS UNSIGNED),
           CAST(m.cantidad_sin_separadores AS UNSIGNED),
           ROUND(CAST(m.cantidad_sin_separadores AS DECIMAL(18,4)) * 10000
                 / CAST(p.cantidad_sin_separadores AS DECIMAL(18,4)), 2)
    FROM poblacion_total_por_provincia AS p
    INNER JOIN medicos_por_provincia AS m
        ON p.nombre_para_unir = m.nombre_para_unir;

    INSERT INTO revision_datos
    SELECT 10, 'Tabla final con 24 provincias y año 2021',
           CONCAT(COUNT(*), ' filas / ', MIN(anio), '-', MAX(anio)), '24 filas / 2021-2021',
           IF(COUNT(*) = 24 AND MIN(anio) = 2021 AND MAX(anio) = 2021, 'CORRECTO', 'ERROR')
    FROM medicos_poblacion_2021;

    INSERT INTO revision_datos
    SELECT 11, 'Tasas finales verificadas con la fórmula',
           CAST(SUM(ABS(medicos_por_10000_aprox - medicos_ponderados_publicados * 10000.0 / poblacion) > 0.005) AS CHAR),
           '0 tasas fuera de tolerancia de redondeo',
           IF(SUM(ABS(medicos_por_10000_aprox - medicos_ponderados_publicados * 10000.0 / poblacion) > 0.005) = 0, 'CORRECTO', 'ERROR')
    FROM medicos_poblacion_2021;

    IF EXISTS (SELECT 1 FROM revision_datos WHERE resultado = 'ERROR') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falló la validación final. Se conserva el resultado anterior.';
    END IF;
    COMMIT;
    SET SESSION SQL_SAFE_UPDATES = modo_seguro_anterior;
    DO RELEASE_LOCK('proyecto_salud_2021_etl');
END$$
DELIMITER ;

CALL preparar_datos_salud();
