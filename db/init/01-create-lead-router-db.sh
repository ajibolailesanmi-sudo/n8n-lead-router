#!/bin/bash
# Runs once, the first time the Postgres container starts with an empty data volume.
# Creates a separate, least-privilege user and database for the lead router.
# n8n keeps its own internal data in the database named by POSTGRES_DB.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  CREATE USER lead_router_app WITH PASSWORD '${LEAD_ROUTER_DB_PASSWORD}';
  CREATE DATABASE lead_router OWNER lead_router_app;
EOSQL

psql -v ON_ERROR_STOP=1 --username lead_router_app --dbname lead_router -f /lead-router/schema.sql

echo "lead_router database and schema created"
