-- ============================================================
-- HEROES SENIOR SOFTBALL — Database Migration
-- Migrate from JSONB to Normalized Relational Schema
-- ============================================================

-- Step 1: Create organizations table
CREATE TABLE IF NOT EXISTS organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  city text,
  state text,
  founded_year integer,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Step 2: Create teams table
CREATE TABLE IF NOT EXISTS teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  legacy_id text UNIQUE,
  name text NOT NULL,
  short_name text,
  division text,
  age_group integer,
  color text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Step 3: Create players table
CREATE TABLE IF NOT EXISTS players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legacy_id text UNIQUE,
  first_name text NOT NULL,
  last_name text NOT NULL,
  number integer,
  position text,
  bats text,
  throws text,
  join_year integer,
  active boolean DEFAULT true,
  photo text,
  email text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Step 4: Create player_roles enum and table
CREATE TYPE player_role AS ENUM ('player', 'coach', 'manager', 'admin');

CREATE TABLE IF NOT EXISTS player_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  role player_role NOT NULL DEFAULT 'player',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(player_id, team_id, role)
);

-- Step 5: Create player_teams junction table
CREATE TABLE IF NOT EXISTS player_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  joined_date date,
  created_at timestamptz DEFAULT now(),
  UNIQUE(player_id, team_id)
);

-- Step 6: Create player_stats table
CREATE TABLE IF NOT EXISTS player_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  game_id uuid,
  season integer,
  at_bats integer DEFAULT 0,
  hits integer DEFAULT 0,
  runs integer DEFAULT 0,
  rbis integer DEFAULT 0,
  doubles integer DEFAULT 0,
  triples integer DEFAULT 0,
  home_runs integer DEFAULT 0,
  walks integer DEFAULT 0,
  strikeouts integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Step 7: Add auto-update triggers
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS organizations_updated_at ON organizations;
CREATE TRIGGER organizations_updated_at
  BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS teams_updated_at ON teams;
CREATE TRIGGER teams_updated_at
  BEFORE UPDATE ON teams
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS players_updated_at ON players;
CREATE TRIGGER players_updated_at
  BEFORE UPDATE ON players
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS player_roles_updated_at ON player_roles;
CREATE TRIGGER player_roles_updated_at
  BEFORE UPDATE ON player_roles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS player_stats_updated_at ON player_stats;
CREATE TRIGGER player_stats_updated_at
  BEFORE UPDATE ON player_stats
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- DATA MIGRATION
-- ============================================================

-- Step 8: Insert organization
INSERT INTO organizations (name, city, state, founded_year)
VALUES ('Heroes Senior Softball', 'Omaha', 'NE', 2021)
ON CONFLICT (name) DO NOTHING;

-- Step 9: Insert teams
WITH org AS (
  SELECT id FROM organizations WHERE name = 'Heroes Senior Softball'
)
INSERT INTO teams (organization_id, legacy_id, name, short_name, division, age_group, color)
SELECT
  org.id,
  team_data->>'id',
  team_data->>'name',
  team_data->>'shortName',
  team_data->>'division',
  (team_data->>'ageGroup')::integer,
  team_data->>'color'
FROM (
  VALUES
    ('{"id": "55s-aaa", "name": "55''s AAA", "shortName": "55s", "division": "AAA", "ageGroup": "55", "color": "#C8102E", "manager": "Mike Marlow", "assistantManager": "James Bennar"}'::jsonb),
    ('{"id": "50s-aaa", "name": "50''s AAA", "shortName": "50s AAA", "division": "AAA", "ageGroup": "50", "color": "#1E3A8A", "manager": "Tony Oliva", "assistantManager": "Gary Jacobsen"}'::jsonb),
    ('{"id": "50s-aa", "name": "50''s AA", "shortName": "50s AA", "division": "AA", "ageGroup": "50", "color": "#16A34A", "manager": "Jeff Martin", "assistantManager": "Chris Mathers"}'::jsonb)
) AS teams(team_data),
org
ON CONFLICT (legacy_id) DO NOTHING;

-- Step 10: Insert players
INSERT INTO players (legacy_id, first_name, last_name, number, position, bats, throws, join_year, active, photo, email)
SELECT
  player_data->>'id',
  player_data->>'firstName',
  player_data->>'lastName',
  (player_data->>'number')::integer,
  player_data->>'position',
  player_data->>'bats',
  player_data->>'throws',
  (player_data->>'joinYear')::integer,
  COALESCE((player_data->>'active')::boolean, true),
  player_data->>'photo',
  player_data->>'email'
FROM (
  VALUES
    ('{"id": "mike-m-001", "firstName": "Mike", "lastName": "Marlow", "number": "1", "position": "C", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/mike-marlow.jpg", "email": ""}'::jsonb),
    ('{"id": "james-b-002", "firstName": "James", "lastName": "Bennar", "number": "2", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/james-bennar.jpg", "email": ""}'::jsonb),
    ('{"id": "tim-d-003", "firstName": "Tim", "lastName": "Dillon", "number": "3", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/tim-dillon.jpg", "email": ""}'::jsonb),
    ('{"id": "mark-p-004", "firstName": "Mark", "lastName": "Popken", "number": "4", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/mark-popken.jpg", "email": ""}'::jsonb),
    ('{"id": "mark-t-005", "firstName": "Mark", "lastName": "Trimble", "number": "5", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/mark-trimble.jpg", "email": ""}'::jsonb),
    ('{"id": "neil-k-006", "firstName": "Neil", "lastName": "Klassen", "number": "6", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/neil-klassen.jpg", "email": ""}'::jsonb),
    ('{"id": "david-m-007", "firstName": "David", "lastName": "Miedema", "number": "7", "position": "C", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/david-miedema.jpg", "email": ""}'::jsonb),
    ('{"id": "rick-w-008", "firstName": "Rick", "lastName": "Workman", "number": "8", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/rick-workman.jpg", "email": ""}'::jsonb),
    ('{"id": "bill-k-009", "firstName": "Bill", "lastName": "Knobel", "number": "9", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/bill-knobel.jpg", "email": ""}'::jsonb),
    ('{"id": "steve-h-010", "firstName": "Steve", "lastName": "Horton", "number": "10", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/steve-horton.jpg", "email": ""}'::jsonb),
    ('{"id": "tony-o-011", "firstName": "Tony", "lastName": "Oliva", "number": "11", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/tony-oliva.jpg", "email": ""}'::jsonb),
    ('{"id": "gary-j-012", "firstName": "Gary", "lastName": "Jacobsen", "number": "12", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/gary-jacobsen.jpg", "email": ""}'::jsonb),
    ('{"id": "jim-h-013", "firstName": "Jim", "lastName": "Hicks", "number": "13", "position": "C", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/jim-hicks.jpg", "email": ""}'::jsonb),
    ('{"id": "rod-s-014", "firstName": "Rod", "lastName": "Springer", "number": "14", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/rod-springer.jpg", "email": ""}'::jsonb),
    ('{"id": "ron-b-015", "firstName": "Ron", "lastName": "Belan", "number": "15", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/ron-belan.jpg", "email": ""}'::jsonb),
    ('{"id": "jerry-s-016", "firstName": "Jerry", "lastName": "Shade", "number": "16", "position": "OF", "bats": "L", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/jerry-shade.jpg", "email": ""}'::jsonb),
    ('{"id": "kevin-t-017", "firstName": "Kevin", "lastName": "Tobin", "number": "17", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/kevin-tobin.jpg", "email": ""}'::jsonb),
    ('{"id": "kip-b-018", "firstName": "Kip", "lastName": "Baird", "number": "18", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/kip-baird.jpg", "email": ""}'::jsonb),
    ('{"id": "ed-b-019", "firstName": "Ed", "lastName": "Bremner", "number": "19", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/ed-bremner.jpg", "email": ""}'::jsonb),
    ('{"id": "jay-g-020", "firstName": "Jay", "lastName": "Guse", "number": "20", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/jay-guse.jpg", "email": ""}'::jsonb),
    ('{"id": "jeff-m-021", "firstName": "Jeff", "lastName": "Martin", "number": "21", "position": "C", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/jeff-martin.jpg", "email": ""}'::jsonb),
    ('{"id": "chris-m-022", "firstName": "Chris", "lastName": "Mathers", "number": "22", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/chris-mathers.jpg", "email": ""}'::jsonb),
    ('{"id": "frank-k-023", "firstName": "Frank", "lastName": "Kitzke", "number": "23", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/frank-kitzke.jpg", "email": ""}'::jsonb),
    ('{"id": "daryl-d-024", "firstName": "Daryl", "lastName": "Dworsky", "number": "24", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/daryl-dworsky.jpg", "email": ""}'::jsonb),
    ('{"id": "ron-k-025", "firstName": "Ron", "lastName": "King", "number": "25", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/ron-king.jpg", "email": ""}'::jsonb),
    ('{"id": "pete-w-026", "firstName": "Pete", "lastName": "Wilson", "number": "26", "position": "OF", "bats": "L", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/pete-wilson.jpg", "email": ""}'::jsonb),
    ('{"id": "rex-h-027", "firstName": "Rex", "lastName": "Hilke", "number": "27", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/rex-hilke.jpg", "email": ""}'::jsonb),
    ('{"id": "bob-t-028", "firstName": "Bob", "lastName": "Tordsen", "number": "28", "position": "C", "bats": "R", "throws": "R", "joinYear": "2021", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/bob-tordsen.jpg", "email": ""}'::jsonb),
    ('{"id": "tom-m-029", "firstName": "Tom", "lastName": "Marsh", "number": "29", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2022", "active": "true", "teams": ["55s-aaa", "50s-aaa"], "photo": "assets/img/players/tom-marsh.jpg", "email": ""}'::jsonb),
    ('{"id": "larry-l-030", "firstName": "Larry", "lastName": "Loftis", "number": "30", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2022", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/larry-loftis.jpg", "email": ""}'::jsonb),
    ('{"id": "mike-l-031", "firstName": "Mike", "lastName": "Ludington", "number": "31", "position": "OF", "bats": "L", "throws": "R", "joinYear": "2022", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/mike-ludington.jpg", "email": ""}'::jsonb),
    ('{"id": "dave-p-032", "firstName": "Dave", "lastName": "Peterson", "number": "32", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2022", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/dave-peterson.jpg", "email": ""}'::jsonb),
    ('{"id": "jim-k-033", "firstName": "Jim", "lastName": "Krupicka", "number": "33", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2022", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/jim-krupicka.jpg", "email": ""}'::jsonb),
    ('{"id": "walt-s-034", "firstName": "Walt", "lastName": "Satterfield", "number": "34", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2022", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/walt-satterfield.jpg", "email": ""}'::jsonb),
    ('{"id": "bob-h-035", "firstName": "Bob", "lastName": "Henne", "number": "35", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2022", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/bob-henne.jpg", "email": ""}'::jsonb),
    ('{"id": "bruce-j-036", "firstName": "Bruce", "lastName": "Jones", "number": "36", "position": "C", "bats": "R", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/bruce-jones.jpg", "email": ""}'::jsonb),
    ('{"id": "doug-d-037", "firstName": "Doug", "lastName": "Durden", "number": "37", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/doug-durden.jpg", "email": ""}'::jsonb),
    ('{"id": "ron-v-038", "firstName": "Ron", "lastName": "Vane", "number": "38", "position": "OF", "bats": "L", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/ron-vane.jpg", "email": ""}'::jsonb),
    ('{"id": "wayne-d-039", "firstName": "Wayne", "lastName": "Denton", "number": "39", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/wayne-denton.jpg", "email": ""}'::jsonb),
    ('{"id": "paul-f-040", "firstName": "Paul", "lastName": "Faber", "number": "40", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/paul-faber.jpg", "email": ""}'::jsonb),
    ('{"id": "bob-l-041", "firstName": "Bob", "lastName": "Linker", "number": "41", "position": "C", "bats": "R", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/bob-linker.jpg", "email": ""}'::jsonb),
    ('{"id": "steve-b-042", "firstName": "Steve", "lastName": "Bloom", "number": "42", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/steve-bloom.jpg", "email": ""}'::jsonb),
    ('{"id": "dan-c-043", "firstName": "Dan", "lastName": "Conlon", "number": "43", "position": "OF", "bats": "R", "throws": "R", "joinYear": "2023", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/dan-conlon.jpg", "email": ""}'::jsonb),
    ('{"id": "walt-w-044", "firstName": "Walt", "lastName": "Walton", "number": "44", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2024", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/walt-walton.jpg", "email": ""}'::jsonb),
    ('{"id": "rod-l-045", "firstName": "Rod", "lastName": "Lehman", "number": "45", "position": "C", "bats": "R", "throws": "R", "joinYear": "2024", "active": "true", "teams": ["55s-aaa"], "photo": "assets/img/players/rod-lehman.jpg", "email": ""}'::jsonb),
    ('{"id": "kevin-b-046", "firstName": "Kevin", "lastName": "Baker", "number": "46", "position": "OF", "bats": "L", "throws": "L", "joinYear": "2024", "active": "true", "teams": ["50s-aaa"], "photo": "assets/img/players/kevin-baker.jpg", "email": ""}'::jsonb),
    ('{"id": "rick-h-047", "firstName": "Rick", "lastName": "Hanson", "number": "47", "position": "IF", "bats": "R", "throws": "R", "joinYear": "2024", "active": "true", "teams": ["50s-aa"], "photo": "assets/img/players/rick-hanson.jpg", "email": ""}'::jsonb)
) AS player_list(player_data)
ON CONFLICT (legacy_id) DO NOTHING;

-- Step 11: Populate player_teams junction table from existing teams arrays
INSERT INTO player_teams (player_id, team_id)
SELECT DISTINCT
  p.id,
  t.id
FROM players p
CROSS JOIN teams t
WHERE (
  (p.legacy_id = 'tom-m-029' AND t.legacy_id IN ('55s-aaa', '50s-aaa'))
  OR (p.legacy_id != 'tom-m-029' AND
      ((p.legacy_id LIKE 'mike-m%' OR p.legacy_id LIKE 'james-b%' OR p.legacy_id LIKE 'tim-d%'
        OR p.legacy_id LIKE 'mark-p%' OR p.legacy_id LIKE 'mark-t%' OR p.legacy_id LIKE 'neil-k%'
        OR p.legacy_id LIKE 'david-m%' OR p.legacy_id LIKE 'rick-w%' OR p.legacy_id LIKE 'bill-k%'
        OR p.legacy_id LIKE 'steve-h%' OR p.legacy_id LIKE 'larry-l%' OR p.legacy_id LIKE 'bruce-j%'
        OR p.legacy_id LIKE 'wayne-d%' OR p.legacy_id LIKE 'steve-b%' OR p.legacy_id LIKE 'rod-l%')
       AND t.legacy_id = '55s-aaa')
      OR ((p.legacy_id LIKE 'tony-o%' OR p.legacy_id LIKE 'gary-j%' OR p.legacy_id LIKE 'jim-h%'
        OR p.legacy_id LIKE 'rod-s%' OR p.legacy_id LIKE 'ron-b%' OR p.legacy_id LIKE 'jerry-s%'
        OR p.legacy_id LIKE 'kevin-t%' OR p.legacy_id LIKE 'kip-b%' OR p.legacy_id LIKE 'ed-b%'
        OR p.legacy_id LIKE 'jay-g%' OR p.legacy_id LIKE 'mike-l%' OR p.legacy_id LIKE 'dave-p%'
        OR p.legacy_id LIKE 'bob-h%' OR p.legacy_id LIKE 'doug-d%' OR p.legacy_id LIKE 'paul-f%'
        OR p.legacy_id LIKE 'dan-c%' OR p.legacy_id LIKE 'kevin-b%')
       AND t.legacy_id = '50s-aaa')
      OR ((p.legacy_id LIKE 'jeff-m%' OR p.legacy_id LIKE 'chris-m%' OR p.legacy_id LIKE 'frank-k%'
        OR p.legacy_id LIKE 'daryl-d%' OR p.legacy_id LIKE 'ron-k%' OR p.legacy_id LIKE 'pete-w%'
        OR p.legacy_id LIKE 'rex-h%' OR p.legacy_id LIKE 'bob-t%' OR p.legacy_id LIKE 'jim-k%'
        OR p.legacy_id LIKE 'walt-s%' OR p.legacy_id LIKE 'ron-v%' OR p.legacy_id LIKE 'bob-l%'
        OR p.legacy_id LIKE 'walt-w%' OR p.legacy_id LIKE 'rick-h%')
       AND t.legacy_id = '50s-aa'))
)
ON CONFLICT (player_id, team_id) DO NOTHING;

-- Step 12: Assign roles based on manager/assistantManager from teams
INSERT INTO player_roles (player_id, team_id, role)
SELECT
  p.id,
  t.id,
  'manager'::player_role
FROM players p
JOIN player_teams pt ON p.id = pt.player_id
JOIN teams t ON pt.team_id = t.id
WHERE (
  (p.legacy_id = 'mike-m-001' AND t.legacy_id = '55s-aaa')
  OR (p.legacy_id = 'james-b-002' AND t.legacy_id = '55s-aaa')
  OR (p.legacy_id = 'tony-o-011' AND t.legacy_id = '50s-aaa')
  OR (p.legacy_id = 'gary-j-012' AND t.legacy_id = '50s-aaa')
  OR (p.legacy_id = 'jeff-m-021' AND t.legacy_id = '50s-aa')
  OR (p.legacy_id = 'chris-m-022' AND t.legacy_id = '50s-aa')
)
ON CONFLICT (player_id, team_id, role) DO NOTHING;

-- Step 13: Enable Row Level Security on new tables
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_stats ENABLE ROW LEVEL SECURITY;

-- Step 14: Create RLS policies (allow all for now - app handles auth)
CREATE POLICY "orgs_read" ON organizations FOR SELECT USING (true);
CREATE POLICY "orgs_insert" ON organizations FOR INSERT WITH CHECK (true);
CREATE POLICY "orgs_update" ON organizations FOR UPDATE USING (true);

CREATE POLICY "teams_read" ON teams FOR SELECT USING (true);
CREATE POLICY "teams_insert" ON teams FOR INSERT WITH CHECK (true);
CREATE POLICY "teams_update" ON teams FOR UPDATE USING (true);

CREATE POLICY "players_read" ON players FOR SELECT USING (true);
CREATE POLICY "players_insert" ON players FOR INSERT WITH CHECK (true);
CREATE POLICY "players_update" ON players FOR UPDATE USING (true);

CREATE POLICY "player_teams_read" ON player_teams FOR SELECT USING (true);
CREATE POLICY "player_teams_insert" ON player_teams FOR INSERT WITH CHECK (true);
CREATE POLICY "player_teams_update" ON player_teams FOR UPDATE USING (true);

CREATE POLICY "player_roles_read" ON player_roles FOR SELECT USING (true);
CREATE POLICY "player_roles_insert" ON player_roles FOR INSERT WITH CHECK (true);
CREATE POLICY "player_roles_update" ON player_roles FOR UPDATE USING (true);

CREATE POLICY "player_stats_read" ON player_stats FOR SELECT USING (true);
CREATE POLICY "player_stats_insert" ON player_stats FOR INSERT WITH CHECK (true);
CREATE POLICY "player_stats_update" ON player_stats FOR UPDATE USING (true);

-- ============================================================
-- VERIFICATION QUERIES (run these to check the migration)
-- ============================================================

-- Check organization
-- SELECT * FROM organizations;

-- Check team count and details
-- SELECT id, name, short_name, division, age_group FROM teams ORDER BY age_group DESC, name;

-- Check player count by team
-- SELECT t.name, COUNT(p.id) as player_count
-- FROM teams t
-- LEFT JOIN player_teams pt ON t.id = pt.team_id
-- LEFT JOIN players p ON pt.player_id = p.id
-- GROUP BY t.id, t.name
-- ORDER BY t.name;

-- Check players with multiple teams (Tom Marsh)
-- SELECT p.first_name, p.last_name, STRING_AGG(t.name, ', ') as teams
-- FROM players p
-- JOIN player_teams pt ON p.id = pt.player_id
-- JOIN teams t ON pt.team_id = t.id
-- GROUP BY p.id, p.first_name, p.last_name
-- HAVING COUNT(DISTINCT pt.team_id) > 1;

-- Check manager roles
-- SELECT p.first_name, p.last_name, t.name, pr.role
-- FROM player_roles pr
-- JOIN players p ON pr.player_id = p.id
-- JOIN teams t ON pr.team_id = t.id
-- WHERE pr.role = 'manager'
-- ORDER BY t.name, p.last_name;
