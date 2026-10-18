-- ============================================================
-- Schéma AquaTrack — tables de base et mises à jour.
-- À exécuter sur la base cible avant de lancer src/seed.js.
-- Les tables sont créées avec IF NOT EXISTS pour permettre une
-- installation initiale ou une mise à jour d'une base existante.
-- ============================================================

-- ============================================================
-- 0. TABLES DE BASE
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          VARCHAR(30) NOT NULL,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ponds (
    id                 SERIAL PRIMARY KEY,
    name               VARCHAR(100) NOT NULL UNIQUE,
    pond_group         VARCHAR(50) NOT NULL,
    area_m2            DECIMAL(10,2) NOT NULL,
    max_capacity       INTEGER NOT NULL,
    current_fish_count INTEGER NOT NULL DEFAULT 0,
    created_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fish_operations (
    id             SERIAL PRIMARY KEY,
    pond_id        INTEGER NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    user_id        INTEGER NOT NULL REFERENCES users(id),
    operation_type VARCHAR(20) NOT NULL
        CHECK (operation_type IN ('addition', 'mortality', 'transfer', 'control')),
    operation_date DATE NOT NULL,
    fish_count     INTEGER NOT NULL,
    avg_weight_g   DECIMAL(10,2),
    target_pond_id INTEGER REFERENCES ponds(id),
    notes          TEXT,
    created_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS water_quality (
    id                  SERIAL PRIMARY KEY,
    pond_id             INTEGER NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    user_id             INTEGER NOT NULL REFERENCES users(id),
    measurement_date    DATE NOT NULL,
    oxygen_level_mg_l   DECIMAL(6,2),
    temperature_c       DECIMAL(6,2),
    water_color         VARCHAR(100),
    created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tasks (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    pond_id     INTEGER REFERENCES ponds(id) ON DELETE SET NULL,
    title       VARCHAR(200) NOT NULL,
    description TEXT,
    priority    VARCHAR(20) NOT NULL
        CHECK (priority IN ('haute', 'moyenne', 'basse')),
    task_date   DATE NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'completed')),
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION update_pond_fish_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.operation_type = 'addition' THEN
        UPDATE ponds
        SET current_fish_count = current_fish_count + NEW.fish_count
        WHERE id = NEW.pond_id;
    ELSIF NEW.operation_type = 'mortality' THEN
        UPDATE ponds
        SET current_fish_count = current_fish_count - NEW.fish_count
        WHERE id = NEW.pond_id;
    ELSIF NEW.operation_type = 'transfer' THEN
        UPDATE ponds
        SET current_fish_count = current_fish_count - NEW.fish_count
        WHERE id = NEW.pond_id;

        UPDATE ponds
        SET current_fish_count = current_fish_count + NEW.fish_count
        WHERE id = NEW.target_pond_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS fish_operations_update_pond_count ON fish_operations;
CREATE TRIGGER fish_operations_update_pond_count
AFTER INSERT ON fish_operations
FOR EACH ROW
EXECUTE FUNCTION update_pond_fish_count();
 
-- ============================================================
-- 1. TABLE daily_feed
--    Stocke la consommation journalière de nourriture par étang
-- ============================================================
 
CREATE TABLE IF NOT EXISTS daily_feed (
    id               SERIAL PRIMARY KEY,
    pond_id          INTEGER REFERENCES ponds(id) ON DELETE CASCADE,
    feed_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    food_given_kg    DECIMAL(10,2) DEFAULT 0,
    food_planned_kg  DECIMAL(10,2) DEFAULT 0,
    created_at       TIMESTAMP DEFAULT NOW()
);
 
-- Contrainte unicité : un seul enregistrement par étang par jour
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'daily_feed_pond_date_unique'
    ) THEN
        ALTER TABLE daily_feed
            ADD CONSTRAINT daily_feed_pond_date_unique
            UNIQUE (pond_id, feed_date);
    END IF;
END$$;
 
 
-- ============================================================
-- 2. TABLE feed_stock
--    Gestion du stock d'aliments avec seuils d'alerte
-- ============================================================
 
CREATE TABLE IF NOT EXISTS feed_stock (
    id                  SERIAL PRIMARY KEY,
    product_name        VARCHAR(100) NOT NULL,
    quantity_kg         DECIMAL(10,2) DEFAULT 0,
    alert_threshold_kg  DECIMAL(10,2) DEFAULT 50,
    updated_at          TIMESTAMP DEFAULT NOW()
);
 
-- Données initiales (insérées seulement si la table est vide)
INSERT INTO feed_stock (product_name, quantity_kg, alert_threshold_kg)
SELECT * FROM (VALUES
    ('Aliment starter',    120.00, 50.00),
    ('Aliment croissance',  85.00, 40.00),
    ('Aliment finition',    30.00, 50.00)
) AS v(product_name, quantity_kg, alert_threshold_kg)
WHERE NOT EXISTS (SELECT 1 FROM feed_stock LIMIT 1);
 
 
-- ============================================================
-- 3. TABLE tasks — ajout colonne assigned_to
--    Permet d'assigner une tâche à un employé spécifique
-- ============================================================
 
ALTER TABLE tasks
    ADD COLUMN IF NOT EXISTS assigned_to INTEGER REFERENCES users(id);
 
 
-- ============================================================
-- 4. TABLE notifications
--    Notifications envoyées depuis l'interface web admin
-- ============================================================
 
CREATE TABLE IF NOT EXISTS notifications (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER REFERENCES users(id),
    message     TEXT NOT NULL,
    is_read     BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMP DEFAULT NOW()
);
 
 
-- ============================================================
-- Vérification finale
-- ============================================================
 
DO $$
BEGIN
    RAISE NOTICE '✓ daily_feed       : OK';
    RAISE NOTICE '✓ feed_stock       : OK';
    RAISE NOTICE '✓ tasks.assigned_to: OK';
    RAISE NOTICE '✓ notifications    : OK';
    RAISE NOTICE '→ Mise à jour terminée sans erreur.';
END$$