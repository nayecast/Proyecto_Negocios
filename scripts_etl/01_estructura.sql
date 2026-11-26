-- Proyecto: médicos y población provincial del Ecuador, año 2021.
-- Ejecutar los scripts en orden con MySQL 8.0.16 o superior.
-- Todas las tablas del proyecto se guardan en la misma base de datos.
-- utf8mb4 es el nombre de MySQL para guardar tildes, ñ y otros símbolos.
-- InnoDB permite deshacer los cambios de una operación si se encuentra un error.
-- Permite guardar correctamente tildes, ñ y otros símbolos.
-- InnoDB permite deshacer los cambios si ocurre un error.
SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS proyecto_salud_2021
    -- Permite comparar nombres aunque cambien las tildes o las mayúsculas.
    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE proyecto_salud_2021;

-- Guarda el nombre de provincia y la cantidad tal como vienen del archivo.
CREATE TABLE IF NOT EXISTS medicos_originales (
    registro_csv INT PRIMARY KEY,
    provincia_original TEXT,
    cantidad_medicos_original TEXT
) ENGINE=InnoDB;

-- Guarda los valores de población y su ubicación en el Excel original.
CREATE TABLE IF NOT EXISTS poblacion_original (
    registro INT PRIMARY KEY,
    hoja VARCHAR(60) NOT NULL,
    fila_excel INT NOT NULL,
    columna_excel INT NOT NULL,
    provincia_original VARCHAR(100),
    sexo_original VARCHAR(1),
    anio_original VARCHAR(10),
    grupo_edad_original VARCHAR(100),
    habitantes_originales VARCHAR(40)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS origen_archivos (
    fuente VARCHAR(20) PRIMARY KEY,
    archivo VARCHAR(100) NOT NULL,
    -- Código que permite comprobar si el archivo original cambió.
    codigo_verificacion CHAR(64) NOT NULL,
    cantidad_registros INT NOT NULL
) ENGINE=InnoDB;

-- Aquí se guarda el resultado final con una fila por provincia y año.
CREATE TABLE IF NOT EXISTS medicos_poblacion_2021 (
    provincia VARCHAR(100) NOT NULL,
    anio SMALLINT NOT NULL,
    poblacion BIGINT NOT NULL,
    -- Cantidad publicada por el INEC, ajustada según las horas de trabajo.
    medicos_ponderados_publicados INT NOT NULL,
    medicos_por_10000_aprox DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (provincia, anio),
    CONSTRAINT revisar_poblacion_positiva CHECK (poblacion > 0),
    CONSTRAINT revisar_cantidad_medicos CHECK (medicos_ponderados_publicados >= 0)
) ENGINE=InnoDB;

-- Aquí se guarda el resultado de las comprobaciones.
CREATE TABLE IF NOT EXISTS revision_datos (
    orden INT PRIMARY KEY,
    control VARCHAR(200) NOT NULL,
    observado VARCHAR(100) NOT NULL,
    esperado VARCHAR(100) NOT NULL,
    resultado VARCHAR(10) NOT NULL
) ENGINE=InnoDB;

-- Las consultas guardadas siguientes preparan los datos para unirlos.
-- UPPER pone las letras en mayúsculas. TRIM quita espacios en los extremos.
-- REGEXP_REPLACE convierte varios espacios seguidos en uno.
-- CONVERT(0xC2A0 USING utf8mb4) reconoce un espacio especial que puede venir de Excel.
-- COLLATE permite comparar nombres aunque tengan diferencias de tildes o mayúsculas.
CREATE OR REPLACE VIEW poblacion_2021_preparada AS
SELECT
    registro, hoja, fila_excel, columna_excel, provincia_original, grupo_edad_original,
    UPPER(TRIM(REGEXP_REPLACE(REPLACE(provincia_original, CONVERT(0xC2A0 USING utf8mb4), ' '), '[[:space:]]+', ' ')))
        COLLATE utf8mb4_0900_ai_ci AS nombre_para_unir,
    UPPER(TRIM(grupo_edad_original)) AS grupo_edad_uniforme,
    TRIM(habitantes_originales) AS cantidad_sin_separadores
FROM poblacion_original
WHERE TRIM(sexo_original) = 'n' AND TRIM(anio_original) = '2021';

CREATE OR REPLACE VIEW poblacion_total_por_provincia AS
SELECT * FROM poblacion_2021_preparada WHERE grupo_edad_uniforme = 'TOTAL';

CREATE OR REPLACE VIEW medicos_con_nombres_uniformes AS
SELECT
    registro_csv, provincia_original, cantidad_medicos_original,
    UPPER(TRIM(REGEXP_REPLACE(REPLACE(provincia_original, CONVERT(0xC2A0 USING utf8mb4), ' '), '[[:space:]]+', ' ')))
        COLLATE utf8mb4_0900_ai_ci AS nombre_para_unir,
    REPLACE(TRIM(cantidad_medicos_original), ',', '') AS cantidad_sin_separadores
FROM medicos_originales;

CREATE OR REPLACE VIEW medicos_por_provincia AS
SELECT m.*
FROM medicos_con_nombres_uniformes AS m
JOIN (SELECT DISTINCT nombre_para_unir FROM poblacion_total_por_provincia) AS p
    ON m.nombre_para_unir = p.nombre_para_unir;
-- Activa la lectura de archivos para hacer la carga
 -- SET GLOBAL local_infile = ON;
-- SET GLOBAL local_infile = OFF;
-- SHOW GLOBAL VARIABLES LIKE 'local_infile';