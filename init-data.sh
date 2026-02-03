#!/bin/bash
set -e

# PostgreSQL initialization script for n8n
# This script creates a non-root user for n8n application access

echo "Starting PostgreSQL initialization for n8n..."

# Create non-root user if it doesn't exist
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create non-root user
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${POSTGRES_NON_ROOT_USER}') THEN
            CREATE USER ${POSTGRES_NON_ROOT_USER} WITH PASSWORD '${POSTGRES_NON_ROOT_PASSWORD}';
            RAISE NOTICE 'User ${POSTGRES_NON_ROOT_USER} created successfully';
        ELSE
            RAISE NOTICE 'User ${POSTGRES_NON_ROOT_USER} already exists';
        END IF;
    END
    \$\$;

    -- Grant all privileges on database to non-root user
    GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_NON_ROOT_USER};
    
    -- Grant schema privileges (for PostgreSQL 15+)
    GRANT ALL ON SCHEMA public TO ${POSTGRES_NON_ROOT_USER};
    
    -- Grant default privileges for future tables
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${POSTGRES_NON_ROOT_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${POSTGRES_NON_ROOT_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${POSTGRES_NON_ROOT_USER};
EOSQL

echo "PostgreSQL initialization completed successfully!"
echo "Non-root user '${POSTGRES_NON_ROOT_USER}' is ready for n8n application."
