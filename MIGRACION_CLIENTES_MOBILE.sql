-- =====================================================================
-- DISTRIC HOUSE — ESQUEMA DE AUTENTICACIÓN DE CLIENTES MÓVILES
-- =====================================================================
-- Propósito: Soportar inicio de sesión, registro, recuperación y sesiones
-- seguras para la aplicación móvil nativa (Android & iOS) sin alterar las tablas
-- ni las consultas existentes del panel de administración ni de los domiciliarios.
-- =====================================================================

CREATE TABLE IF NOT EXISTS pedidos_app_customer_accounts (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(50) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  default_address TEXT,
  default_barrio VARCHAR(255),
  reset_token VARCHAR(255),
  reset_token_expiry TIMESTAMPTZ,
  email_verified BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_accounts_email ON pedidos_app_customer_accounts (LOWER(email));
CREATE INDEX IF NOT EXISTS idx_customer_accounts_phone ON pedidos_app_customer_accounts (phone);
