-- ==============================================================================
-- TALLER PRÁCTICO: OPTIMIZACIÓN DE CONSULTAS Y RENDIMIENTO EN MYSQL (BancoDB)
-- ==============================================================================
-- Objetivo: Que los estudiantes diagnostiquen consultas lentas usando EXPLAIN ANALYZE,
-- identifiquen lecturas completas de tabla (Table Scans), reescriban consultas
-- de forma sargable y apliquen índices compuestos y cubrientes sobre la base de datos bancaria.
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS BancoDB;
USE BancoDB;

-- ------------------------------------------------------------------------------
-- PARTE 0: ESTRUCTURA DE TABLAS E POBLAMIENTO DE DATOS MASIVOS
-- ------------------------------------------------------------------------------

DROP TABLE IF EXISTS historial_transferencias;
DROP TABLE IF EXISTS cuentas;

CREATE TABLE cuentas (
    id_cuenta INT PRIMARY KEY AUTO_INCREMENT,
    titular VARCHAR(100) NOT NULL,
    tipo_cuenta VARCHAR(20) NOT NULL DEFAULT 'Ahorros',
    saldo DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    estado VARCHAR(20) NOT NULL DEFAULT 'Activa',
    fecha_apertura DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE historial_transferencias (
    id_transferencia INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_origen INT NOT NULL,
    cuenta_destino INT NOT NULL,
    monto DECIMAL(12, 2) NOT NULL,
    estado_transferencia VARCHAR(20) NOT NULL DEFAULT 'Exitosa',
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cuenta_origen) REFERENCES cuentas(id_cuenta),
    FOREIGN KEY (cuenta_destino) REFERENCES cuentas(id_cuenta)
);

-- Procedimiento auxiliar para generar un volumen masivo de prueba (para notar diferencias de tiempo)
DELIMITER //
CREATE PROCEDURE CargarDatosPrueba()
BEGIN
    DECLARE i INT DEFAULT 1;
    
    -- Insertar 1,000 cuentas
    WHILE i <= 1000 DO
        INSERT INTO cuentas (titular, tipo_cuenta, saldo, estado, fecha_apertura)
        VALUES (
            CONCAT('Cliente_', i),
            IF(i % 2 = 0, 'Ahorros', 'Corriente'),
            ROUND(RAND() * 10000000, 2),
            IF(i % 10 = 0, 'Bloqueada', 'Activa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY)
        );
        SET i = i + 1;
    END WHILE;

    -- Insertar 10,000 transferencias
    SET i = 1;
    WHILE i <= 10000 DO
        INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto, estado_transferencia, fecha)
        VALUES (
            FLOOR(1 + RAND() * 999),
            FLOOR(1 + RAND() * 999),
            ROUND(1000 + RAND() * 500000, 2),
            IF(i % 15 = 0, 'Fallida', 'Exitosa'),
            DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 180) DAY)
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

-- Ejecutar la carga masiva
CALL CargarDatosPrueba();
DROP PROCEDURE IF EXISTS CargarDatosPrueba;


-- ==============================================================================
-- PARTE 1: DEMOSTRACIÓN GUIADA EN CLASE (PROFESOR)
-- ==============================================================================

-- PROBLEMA: Búsqueda de transferencias por estado y rango de fechas sin índice secundario.
-- Analizar el costo de ejecución antes de optimizar:
EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';

-- DIAGNÓSTICO:
-- Observar en la salida 'Table scan on historial_transferencias' y el costo alto.

-- SOLUCIÓN DEMOSTRATIVA: Crear índice compuesto ordenado por discriminación.
CREATE INDEX idx_transf_estado_fecha ON historial_transferencias(estado_transferencia, fecha);

-- RE-EVALUACIÓN:
EXPLAIN ANALYZE
SELECT id_transferencia, cuenta_origen, monto, fecha
FROM historial_transferencias
WHERE estado_transferencia = 'Exitosa'
  AND fecha >= '2026-01-01 00:00:00';


-- ==============================================================================
-- PARTE 2: EJERCICIOS PRÁCTICOS PARA LOS ESTUDIANTES (A IMPLEMENTAR)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- EJERCICIO 1: Diagnóstico de "Non-Sargable Query" (Uso de Funciones en WHERE)
-- ------------------------------------------------------------------------------
-- ENUNCIADO: El sistema ejecuta la siguiente consulta para obtener las transferencias
-- realizadas en un día específico. El desarrollador anterior aplicó la función DATE() 
-- sobre la columna 'fecha'.
-- 
-- BASE INEFICIENTE (A ejecutar y analizar):
EXPLAIN ANALYZE
SELECT * 
FROM historial_transferencias 
WHERE DATE(fecha) = '2026-02-15';

-- TAREA DEL ESTUDIANTE:
-- 1. Explica por qué el índice 'idx_transf_estado_fecha' NO es utilizado por MySQL en la consulta anterior.
-- 2. Reescribe la consulta de forma "sargable" (utilizando rangos de fechas sin envolver la columna en funciones).
-- 3. Compara el plan de ejecución con EXPLAIN ANALYZE.

-- [ESCRIBE TU SOLUCIÓN AQUÍ]

-- 1. Justificación:
-- El índice idx_transf_estado_fecha no se utiliza porque 'fecha' es la segunda columna del índice
-- y no se filtró por la primera (estado_transferencia). Además, la función DATE(fecha) oculta el valor
-- de la columna al optimizador (Non-Sargable), forzando un Table Scan fila por fila.
  
-- 2. Consulta SARGable optimizada por rango:
EXPLAIN ANALYZE
SELECT * 
FROM historial_transferencias 
WHERE fecha >= '2026-02-15 00:00:00' 
   AND fecha < '2026-02-16 00:00:00';
  
-- 3. Creación de índice específico sobre fecha para optimizar el rango:
CREATE INDEX idx_transf_fecha ON historial_transferencias(fecha);
  
-- Re-evaluación con índice en fecha:
EXPLAIN ANALYZE
SELECT * 
FROM historial_transferencias 
WHERE fecha >= '2026-02-15 00:00:00' 
   AND fecha < '2026-02-16 00:00:00';

-- ------------------------------------------------------------------------------
-- EJERCICIO 2: Optimización mediante Índices Cubrientes (Covering Index)
-- ------------------------------------------------------------------------------
-- ENUNCIADO: La aplicación consulta frecuentemente el saldo y tipo de cuenta de clientes activos
-- para validar autorizaciones rápidas.
--
-- BASE INEFICIENTE:
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';

-- TAREA DEL ESTUDIANTE:
-- 1. Analiza el impacto de usar SELECT * vs seleccionar solo los campos estrictamente necesarios.
-- 2. Diseña un Índice Cubriente (Covering Index) que contenga la columna del WHERE y los campos retornados.
-- 3. Ejecuta EXPLAIN ANALYZE y verifica que la salida indique "Using index" (evitando ir a buscar filas a la tabla base).

-- [ESCRIBE TU SOLUCIÓN AQUÍ]

-- 1. Análisis:
-- SELECT * obliga a buscar todas las columnas en la tabla base (clúster), impidiendo que un índice
-- secundario satisfaga la consulta por sí solo. Al especificar únicamente los campos requeridos,
-- es posible cubrirlos todos dentro de un índice sin tocar la tabla (evitando I/O de disco).
  
-- 2. Creación del Índice Cubriente:
CREATE INDEX idx_cuentas_estado_cubriente ON cuentas(estado, titular, saldo, tipo_cuenta);
  
-- 3. Verificación con EXPLAIN ANALYZE:
EXPLAIN ANALYZE
SELECT titular, saldo, tipo_cuenta
FROM cuentas
WHERE estado = 'Activa';

-- ------------------------------------------------------------------------------
-- EJERCICIO 3: Optimización de Filtros Combinados y JOINs
-- ------------------------------------------------------------------------------
-- ENUNCIADO: Se requiere generar un reporte de los clientes con cuentas activas que hayan realizado
-- transferencias superiores a $300,000 en los últimos 30 días.
--
-- BASE INEFICIENTE:
EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- TAREA DEL ESTUDIANTE:
-- 1. Ejecuta EXPLAIN ANALYZE e identifica cuál tabla es escaneada por completo (Full Table Scan).
-- 2. Diseña los índices necesarios en la tabla 'cuentas' y/o 'historial_transferencias' para optimizar la unión (JOIN) y el filtro.
-- 3. Justifica el orden de las columnas en el índice creado.

-- [ESCRIBE TU SOLUCIÓN AQUÍ]

 -- 1. Diagnóstico:
-- La tabla 'historial_transferencias' (ht) es escaneada por completo (Table scan on ht)
-- debido a que no posee un índice para evaluar el filtro 'ht.monto > 300000.00'.
  
-- 2. Creación del índice optimizado para filtro y JOIN:
CREATE INDEX idx_transf_monto_origen ON historial_transferencias(monto, cuenta_origen, fecha);
  
-- 3. Justificación del orden:
-- Se ubica 'monto' como columna inicial para filtrar el rango directamente en el índice.
-- 'cuenta_origen' y 'fecha' se incluyen para satisfacer la condición del JOIN y las columnas
-- del SELECT como índice cubriente, eliminando la necesidad de leer la tabla base.
  
-- Verificación con EXPLAIN ANALYZE:
EXPLAIN ANALYZE
SELECT c.id_cuenta, c.titular, ht.id_transferencia, ht.monto, ht.fecha
FROM cuentas c
JOIN historial_transferencias ht ON c.id_cuenta = ht.cuenta_origen
WHERE c.estado = 'Activa'
  AND ht.monto > 300000.00;

-- ==============================================================================
-- FIN DEL TALLER
-- ==============================================================================
