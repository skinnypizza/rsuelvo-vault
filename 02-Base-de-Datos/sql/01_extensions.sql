-- ============================================================
-- RSUELVO :: EXTENSIONES Y ESQUEMA
-- Archivo 01/12 del schema separado
-- Ejecutar en orden. Idempotente. Esquema: rsuelvo
-- ============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

create schema if not exists rsuelvo;

-- NOTA: ejecutar 01..12 en orden. Cada archivo es autónomo e idempotente.
