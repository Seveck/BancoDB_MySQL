-- ==============================================================================
-- TALLER PRÁCTICO: TRIGGERS Y EVENTOS EN MYSQL (BancoDB)
-- ==============================================================================
-- Objetivo: Comprender la creación y funcionamiento de Triggers (reactividad en
-- tiempo real) y Eventos (programación temporal de tareas) sobre la base de datos BancoDB.
-- ==============================================================================

USE BancoDB;

-- ------------------------------------------------------------------------------
-- PARTE 0: TABLAS DE AUDITORÍA Y MÉTRICAS (Estructura de Soporte)
-- ------------------------------------------------------------------------------

-- Tabla para auditar cambios de saldo en tiempo real (Usada por el Trigger)
CREATE TABLE IF NOT EXISTS auditoria_saldos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_cuenta INT NOT NULL,
    saldo_anterior DECIMAL(10,2) NOT NULL,
    saldo_nuevo DECIMAL(10,2) NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    fecha_modificacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cuenta) REFERENCES cuentas(id_cuenta)
);

-- Tabla para guardar métricas consolidadas del sistema (Usada por el Evento)
CREATE TABLE IF NOT EXISTS metricas_diarias (
    id_metrica INT AUTO_INCREMENT PRIMARY KEY,
    fecha_metrica DATE NOT NULL,
    total_cuentas INT NOT NULL,
    saldo_total_sistema DECIMAL(12,2) NOT NULL,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Asegurar que el programador de eventos esté encendido en el servidor
SET GLOBAL event_scheduler = ON;

-- ------------------------------------------------------------------------------
-- PARTE 1: DEMOSTRACIÓN GUIADA EN CLASE (EXPLICACIÓN DEL PROFESOR)
-- ------------------------------------------------------------------------------

-- 1.1 TRIGGER DEMOSTRACIÓN: Auditoría Automática de Cambios de Saldo
-- Tipo: AFTER UPDATE sobre la tabla 'cuentas'
-- Concepto: Captura los valores previos (OLD) y nuevos (NEW) tras una actualización.

DELIMITER //

DROP TRIGGER IF EXISTS trg_auditar_cambio_saldo //

CREATE TRIGGER trg_auditar_cambio_saldo
AFTER UPDATE ON cuentas
FOR EACH ROW
BEGIN
    -- Detectar si hubo una modificación efectiva en la columna saldo
    IF OLD.saldo <> NEW.saldo THEN
        INSERT INTO auditoria_saldos (
            id_cuenta, 
            saldo_anterior, 
            saldo_nuevo, 
            usuario
        ) 
        VALUES (
            NEW.id_cuenta, 
            OLD.saldo, 
            NEW.saldo, 
            USER()
        );
    END IF;
END //

DELIMITER ;

-- PRUEBA EN CLASE:
UPDATE cuentas SET saldo = saldo + 500.00 WHERE id_cuenta = 1;
SELECT * FROM auditoria_saldos;


-- 1.2 EVENTO DEMOSTRACIÓN: Resumen Periódico de Métricas del Banco
-- Tipo: RECURRING (Se ejecuta automáticamente según un intervalo)
-- Concepto: Tarea asíncrona en segundo plano que no depende de la interacción del usuario.

DELIMITER //

DROP EVENT IF EXISTS evt_registrar_metricas_diarias //

CREATE EVENT evt_registrar_metricas_diarias
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Consolida el saldo total y cantidad de cuentas activas diariamente'
DO
BEGIN
    INSERT INTO metricas_diarias (fecha_metrica, total_cuentas, saldo_total_sistema)
    SELECT 
        CURDATE(),
        COUNT(id_cuenta),
        IFNULL(SUM(saldo), 0.00)
    FROM cuentas
    WHERE estado = 'Activa';
END //

DELIMITER ;

-- PRUEBA EN CLASE:
SHOW EVENTS FROM BancoDB;
SELECT * FROM metricas_diarias;


-- ==============================================================================
-- PARTE 2: RETO AUTÓNOMO PARA LOS ESTUDIANTES (PARA IMPLEMENTAR EN CLASE)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- EJERCICIO 1 (TRIGGER): Validación de Transferencias (BEFORE INSERT)
-- ------------------------------------------------------------------------------
-- ENUNCIADO PARA EL ESTUDIANTE:
-- Crea un Trigger llamado `trg_validar_transferencia` que se active BEFORE INSERT 
-- en la tabla `historial_transferencias`.
--
-- REGLAS DE NEGOCIO QUE DEBE VALIDAR EL TRIGGER:
-- 1. El monto a transferir debe ser estrictamente mayor a cero (> 0).
-- 2. La `cuenta_origen` y la `cuenta_destino` NO pueden ser la misma cuenta.
-- 3. Si no se cumple alguna regla, abortar la operación usando SIGNAL SQLSTATE '45000'
--    con un mensaje explicativo (ej. 'El monto de la transferencia debe ser mayor a cero' 
--    o 'La cuenta de origen y destino no pueden ser iguales').
-- ------------------------------------------------------------------------------

DELIMITER //

DROP TRIGGER IF EXISTS trg_validar_transferencia //

CREATE TRIGGER trg_validar_transferencia
BEFORE INSERT ON historial_transferencias
FOR EACH ROW
BEGIN
    IF NEW.monto <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El monto de la transferencia debe ser mayor a cero';
    ELSEIF NEW.cuenta_origen = NEW.cuenta_destino THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La cuenta de origen y destino no pueden ser iguales';
    END IF;
END //

DELIMITER ;

-- PRUEBAS EJERCICIO 1:
-- Caso 1: Error por monto inválido (<= 0)
INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 2, -50.00);

-- Caso 2: Error por cuentas iguales (origen = destino)
INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 1, 100.00);

-- Caso 3: Inserción válida exitosa
INSERT INTO historial_transferencias (cuenta_origen, cuenta_destino, monto) VALUES (1, 2, 100.00);


-- ------------------------------------------------------------------------------
-- EJERCICIO 2 (EVENTO): Inactivación Automática de Cuentas en Cero
-- ------------------------------------------------------------------------------
-- ENUNCIADO PARA EL ESTUDIANTE:
-- Crea un Evento programado llamado `evt_inactivar_cuentas_vacias` que se ejecute 
-- cada semana (EVERY 1 WEEK) o cada día (EVERY 1 DAY).
--
-- TAREA DEL EVENTO:
-- Actualizar la tabla `cuentas` cambiando el campo `estado` a 'Inactiva' para todas 
-- aquellas cuentas cuyo saldo sea igual a 0.00 y que actualmente estén en estado 'Activa'.
-- ------------------------------------------------------------------------------

DELIMITER //

DROP EVENT IF EXISTS evt_inactivar_cuentas_vacias //

CREATE EVENT evt_inactivar_cuentas_vacias
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Inactivación automática de cuentas en cero'
DO
BEGIN
    UPDATE cuentas
    SET estado = 'Inactiva'
    WHERE saldo = 0.00 AND estado = 'Activa';
END //

DELIMITER ;

-- PRUEBAS EJERCICIO 2:
SHOW EVENTS FROM BancoDB;
