-- Leer los archivos CSV de la carpeta que indicó el grupo.
-- Si se mueve el proyecto, actualizar las tres rutas escritas entre comillas.
-- MySQL y la conexión de Workbench deben permitir LOAD DATA LOCAL INFILE.
-- Las instrucciones para activar esa lectura están en README.md.
SET NAMES utf8mb4;
USE proyecto_salud_2021;

-- Primero se leen los archivos en tablas temporales de esta conexión.
DROP TEMPORARY TABLE IF EXISTS importar_medicos;
DROP TEMPORARY TABLE IF EXISTS importar_poblacion;
DROP TEMPORARY TABLE IF EXISTS importar_origen;
CREATE TEMPORARY TABLE importar_medicos LIKE medicos_originales;
CREATE TEMPORARY TABLE importar_poblacion LIKE poblacion_original;
CREATE TEMPORARY TABLE importar_origen LIKE origen_archivos;

SET @avisos_medicos = 1, @avisos_poblacion = 1, @avisos_origen = 1;

-- Leer las filas del archivo de médicos.
LOAD DATA LOCAL INFILE 'C:/Users/LENOVO LEGION 5/OneDrive/Documentos/5ciclo/Negocios/proyecto/datos_importacion/medicos_para_cargar.csv'
INTO TABLE importar_medicos
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(registro_csv, provincia_original, cantidad_medicos_original);
GET DIAGNOSTICS @avisos_medicos = NUMBER;

-- Leer todas las filas del archivo de población.
LOAD DATA LOCAL INFILE 'C:/Users/LENOVO LEGION 5/OneDrive/Documentos/5ciclo/Negocios/proyecto/datos_importacion/poblacion_para_cargar.csv'
INTO TABLE importar_poblacion
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(registro, hoja, fila_excel, columna_excel, provincia_original,
 sexo_original, anio_original, grupo_edad_original, habitantes_originales);
GET DIAGNOSTICS @avisos_poblacion = NUMBER;

-- Leer la procedencia y las cantidades esperadas de registros.
LOAD DATA LOCAL INFILE 'C:/Users/LENOVO LEGION 5/OneDrive/Documentos/5ciclo/Negocios/proyecto/datos_importacion/origen_archivos.csv'
INTO TABLE importar_origen
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(fuente, archivo, codigo_verificacion, cantidad_registros);
GET DIAGNOSTICS @avisos_origen = NUMBER;

-- Guardar las fuentes cuando se hayan leído correctamente los tres archivos.
DROP PROCEDURE IF EXISTS confirmar_carga_archivos;
DELIMITER $$
CREATE PROCEDURE confirmar_carga_archivos()
BEGIN
    DECLARE filas_medicos INT;
    DECLARE filas_poblacion INT;
    DECLARE archivos_leidos INT;
    DECLARE medicos_esperados INT;
    DECLARE poblacion_esperada INT;
    DECLARE modo_seguro_anterior INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET SESSION SQL_SAFE_UPDATES = modo_seguro_anterior;
        RESIGNAL;
    END;

    SET modo_seguro_anterior = @@SESSION.sql_safe_updates;
    SELECT COUNT(*) INTO filas_medicos FROM importar_medicos;
    SELECT COUNT(*) INTO filas_poblacion FROM importar_poblacion;
    SELECT COUNT(*),
           MAX(CASE WHEN fuente = 'medicos' THEN cantidad_registros END),
           MAX(CASE WHEN fuente = 'poblacion' THEN cantidad_registros END)
    INTO archivos_leidos, medicos_esperados, poblacion_esperada
    FROM importar_origen;

    IF COALESCE(@avisos_medicos, 1) > 0
       OR COALESCE(@avisos_poblacion, 1) > 0
       OR COALESCE(@avisos_origen, 1) > 0
       OR archivos_leidos <> 2
       OR filas_medicos = 0 OR filas_poblacion = 0
       OR filas_medicos <> COALESCE(medicos_esperados, 0)
       OR filas_poblacion <> COALESCE(poblacion_esperada, 0)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Revise las rutas, los CSV y los avisos de lectura antes de guardar la carga.';
    END IF;

    START TRANSACTION;
    -- Permitir reemplazar las filas de estas tablas durante la carga.
    SET SESSION SQL_SAFE_UPDATES = 0;
    DELETE FROM medicos_originales;
    DELETE FROM poblacion_original;
    DELETE FROM origen_archivos;
    INSERT INTO medicos_originales SELECT * FROM importar_medicos;
    INSERT INTO poblacion_original SELECT * FROM importar_poblacion;
    INSERT INTO origen_archivos SELECT * FROM importar_origen;
    COMMIT;
    -- Recuperar la configuración que tenía esta conexión al comenzar.
    SET SESSION SQL_SAFE_UPDATES = modo_seguro_anterior;
END$$
DELIMITER ;
CALL confirmar_carga_archivos();

SELECT 'Médicos' AS fuente, COUNT(*) AS filas_cargadas FROM medicos_originales
UNION ALL
SELECT 'Población', COUNT(*) FROM poblacion_original;
