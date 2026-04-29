-- KioskConfig
-- Purpose: Centralised, authoritative data for all kiosk selection steps
--          and per-simulation parameters. Shared between:
--            • Server  — KioskController (display names), simulation modules
--                        (stepNames / maxTimes pulled from here instead of
--                        being hard-coded in each module)
--            • Client  — ConfirmationUIHandler (populates the ConfirmationUI
--                        ScreenGui before the player confirms)
-- Location: ReplicatedStorage.Shared.KioskConfig

local KioskConfig = {}

------------------------------------------------------------------------
-- MODES
-- `name`  — the button Name as it appears in the SurfaceGui ModeSelector
--           and the string passed to SimulationStartBindable.
-- `display`     — human-readable label shown in UI.
-- `description` — one-sentence summary shown in ConfirmationUI.
------------------------------------------------------------------------
KioskConfig.MODES = {
	{
		name = "FireSimulation",
		display = "Simulacro de Incendio",
		description = "Protocolo de evacuación ante incendio en instalaciones.",
	},
	{
		name = "EarthquakeSimulation",
		display = "Simulacro de Sismo",
		description = "Protocolo de protección y evacuación ante terremoto.",
	},
	{
		name = "ArmedGroupsSimulation",
		display = "Simulacro de Grupos Armados",
		description = "Protocolo de confinamiento ante presencia de amenaza armada.",
	},
	{
		name = "ExploreSimulation",
		display = "Exploración Libre",
		description = "Recorre el entorno sin simulacro activo.",
	},
}

------------------------------------------------------------------------
-- DIFFICULTIES
-- `name`  — the button Name as it appears in the SurfaceGui DiffSelector
--           and the string passed to SimulationStartBindable.
-- `level` — numeric level used by DIFFICULTY_MAP in SimulationController.
------------------------------------------------------------------------
KioskConfig.DIFFICULTIES = {
	{
		name = "Easy",
		display = "Fácil",
		level = 1,
		description = "Condiciones óptimas. Ideal para la primera experiencia.",
	},
	{
		name = "Medium",
		display = "Medio",
		level = 2,
		description = "Condiciones intermedias. Presión moderada.",
	},
	{
		name = "Hard",
		display = "Difícil",
		level = 3,
		description = "Condiciones extremas. Para participantes experimentados.",
	},
}

------------------------------------------------------------------------
-- SIMULATION STEPS
-- This is the single source of truth previously hard-coded in each
-- simulation module:
--   stepNames — displayed in HUD objectives and Results screen rows.
--   maxTimes  — per-step time targets (seconds) used by ScoringSystem.
--   description — brief flow summary shown in ConfirmationUI.
------------------------------------------------------------------------
KioskConfig.SIMULATION_STEPS = {
	FireSimulation = {
		-- Short labels: used in the HUD objective list and the results screen.
		stepNames = { "Deteccion", "Alarma", "Evacuacion", "Punto de encuentro" },
		-- Detailed labels: shown in ConfirmationUI before the simulation starts.
		stepNamesDetailed = {
			"Localizar e identificar el foco de incendio señalado",
			"Dirigirse al punto de alarma y activarla",
			"Evacuar el edificio por las salidas de emergencia",
			"Reunirse en el punto de encuentro externo",
		},
		maxTimes = { 15, 10, 20, 15 },
		description = "4 pasos: Identificar el foco → Activar la alarma → Evacuar → Punto de encuentro.",
	},
	EarthquakeSimulation = {
		stepNames = { "Refugiarse", "Evacuacion", "Zona segura" },
		stepNamesDetailed = {
			"Agacharse, cubrirse y agarrarse bajo una estructura resistente",
			"Evacuar el edificio de forma ordenada usando las escaleras",
			"Dirigirse a la zona segura exterior e identificarse",
		},
		maxTimes = { 12, 18, 15 },
		description = "3 pasos: Refugiarse bajo estructura → Evacuar el edificio → Zona segura exterior.",
	},
	ArmedGroupsSimulation = {
		stepNames = { "Alerta", "Confinamiento", "Verificacion", "Evacuacion" },
		stepNamesDetailed = {
			"Activar la alerta institucional en el punto señalado",
			"Confinarse en el espacio seguro, cerrar con llave y apagar luces",
			"Acudir al punto de verificación con las manos visibles",
			"Evacuar de forma ordenada al punto de reunión externo",
		},
		maxTimes = { 10, 20, 15, 18 },
		description = "4 pasos: Activar alerta → Confinamiento → Verificación de identidad → Evacuación.",
	},
	ExploreSimulation = {
		stepNames = {},
		stepNamesDetailed = {},
		maxTimes = {},
		description = "Exploración libre. Sin objetivos cronometrados.",
	},
}

------------------------------------------------------------------------
-- LOOKUP HELPERS
------------------------------------------------------------------------

-- Returns the full mode entry for a given name key, or nil.
function KioskConfig.getModeData(name)
	for _, m in ipairs(KioskConfig.MODES) do
		if m.name == name then
			return m
		end
	end
	return nil
end

-- Returns the full difficulty entry for a given name key, or nil.
function KioskConfig.getDifficultyData(name)
	for _, d in ipairs(KioskConfig.DIFFICULTIES) do
		if d.name == name then
			return d
		end
	end
	return nil
end

-- Returns the full difficulty entry for a numeric level (1/2/3), or nil.
function KioskConfig.getDifficultyByLevel(level)
	for _, d in ipairs(KioskConfig.DIFFICULTIES) do
		if d.level == level then
			return d
		end
	end
	return nil
end

-- Returns the steps table for a simulation type.
-- Always safe: returns a table with empty stepNames/maxTimes if unknown.
function KioskConfig.getSteps(simType)
	return KioskConfig.SIMULATION_STEPS[simType] or { stepNames = {}, maxTimes = {}, description = "" }
end

-- Convenience: display name for a mode key (falls back to raw key).
function KioskConfig.getModeDisplay(name)
	local m = KioskConfig.getModeData(name)
	return m and m.display or name
end

-- Convenience: display name for a difficulty key (falls back to raw key).
function KioskConfig.getDifficultyDisplay(name)
	local d = KioskConfig.getDifficultyData(name)
	return d and d.display or name
end

return KioskConfig
