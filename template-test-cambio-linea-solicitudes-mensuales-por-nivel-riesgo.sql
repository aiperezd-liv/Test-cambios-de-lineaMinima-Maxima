/***********************************************************************************************************************
  REPORTE COMPACTO: VOLUMEN MENSUAL DE SOLICITUDES PIVOTADO POR NIVEL DE RIESGO NUMÉRICO
  PERIODO: ENERO 2024 - MAYO 2026 (CON FILTRO EXTRACTOR PARA HIT / NOHIT)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: CONTEO ABSOLUTO DE SOLICITUDES POR MES, BURÓ Y RIESGO
------------------------------------------------------------------------------------------------------------------------
WITH SOLICITUDES_AGRUPADAS AS (
  SELECT
      DATE_TRUNC(DT_FCH_SOL, MONTH) AS COSECHA, -- Agrupa por el primer día de cada mes
      BR_HIT_DES,
      BR_NIVEL_RIESGO,
      COUNT(*) AS TOTAL_SOLICITUDES
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2024-01-01' AND '2026-05-31'  -- <<< PERIODO ACTUALIZADO HASTA MAYO 2026
    AND BR_ORG = 210
    AND CTA_CVE > 0
    AND BR_HIT_DES IN ('HIT', 'NOHIT')
    -- Filtro estricto para ignorar valores nulos o no asignados
    AND BR_NIVEL_RIESGO IS NOT NULL
  GROUP BY 1, 2, 3
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: MATRIZ DE VOLUMEN MENSUAL PIVOTADA POR GRUPO DE RIESGO (0 AL 5)
------------------------------------------------------------------------------------------------------------------------
SELECT 
    COSECHA,
    -- Suma total de solicitudes del mes para el segmento filtrado
    SUM(TOTAL_SOLICITUDES) AS TOTAL_SOLICITUDES_MES,

    -- Columnas pivotadas con el volumen de solicitudes por cada nivel de riesgo
    COALESCE(SUM(CASE WHEN BR_NIVEL_RIESGO = 0 THEN TOTAL_SOLICITUDES END), 0) AS SOLICITUDES_R0,
    COALESCE(SUM(CASE WHEN BR_NIVEL_RIESGO = 1 THEN TOTAL_SOLICITUDES END), 0) AS SOLICITUDES_R1,
    COALESCE(SUM(CASE WHEN BR_NIVEL_RIESGO = 2 THEN TOTAL_SOLICITUDES END), 0) AS SOLICITUDES_R2,
    COALESCE(SUM(CASE WHEN BR_NIVEL_RIESGO = 3 THEN TOTAL_SOLICITUDES END), 0) AS SOLICITUDES_R3,
    COALESCE(SUM(CASE WHEN BR_NIVEL_RIESGO = 4 THEN TOTAL_SOLICITUDES END), 0) AS SOLICITUDES_R4,
    COALESCE(SUM(CASE WHEN BR_NIVEL_RIESGO = 5 THEN TOTAL_SOLICITUDES END), 0) AS SOLICITUDES_R5

FROM SOLICITUDES_AGRUPADAS

-- >>> FILTRO ÚNICO DE EXTRACCIÓN INTERCAMBIABLE:
WHERE BR_HIT_DES = 'NOHIT'      -- Cambiar a 'NOHIT' para extraer la otra matriz

GROUP BY 1
ORDER BY COSECHA ASC;
