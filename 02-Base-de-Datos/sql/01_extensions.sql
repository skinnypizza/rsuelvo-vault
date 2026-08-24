-- ============================================================
-- RSUELVO v2 :: 1. EXTENSIONES Y ESQUEMA
-- ============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

create schema if not exists rsuelvo;

set search_path = rsuelvo, public;
