/***********************************************************************************************************************
  ANÁLISIS DE COSECHAS: PROMEDIO MENSUAL DE MORAS POR SALDO (PIVOTADO POR NIVEL DE RIESGO NUMÉRICO)
  PERIODO: ENERO 2024 - AGOSTO 2025 (CON FILTRO EXTRACTOR PARA HIT / NOHIT)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: UNIVERSO DE SOLICITUDES Y FILTRADO DE CASOS NULOS
------------------------------------------------------------------------------------------------------------------------
WITH LINEAS AS (
  SELECT
      CTA_CVE,
      BR_HIT_DES,
      BR_NIVEL_RIESGO,  -- Campo numérico (0 al 5)
      DATE_TRUNC(DT_FCH_SOL, MONTH) AS COSECHA  
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2024-07-01' AND '2025-08-31'
    AND BR_ORG = 210
    AND CTA_CVE > 0
    AND BR_HIT_DES IN ('HIT', 'NOHIT')
    -- >>> SE ELIMINAN REGISTROS NULOS O SIN RIESGO ASIGNADO:
    AND BR_NIVEL_RIESGO IS NOT NULL 
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: HISTÓRICO DE SALDOS MENSUALES Y MOB
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_NIV_MOR,
      a.CTA_SDO_ACT,
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b
    USING (CTA_CVE)
  WHERE a.TIP_INF = 210
    AND a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2024
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: COMPORTAMIENTO DE SALDOS POR VENTANAS DE TIEMPO
------------------------------------------------------------------------------------------------------------------------
MORAS AS (
  SELECT
      CTA_CVE,
      -- VENTANA MOB 2 (Mora Temprana / Entry)
      MAX(CASE WHEN MOB = 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_2M,
      MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_ENTRY_2M, 
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: CONSOLIDACIÓN DE UNIVERSOS
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_CONSOLIDADO AS (
  SELECT 
      l.COSECHA,
      l.BR_HIT_DES,
      l.BR_NIVEL_RIESGO,
      m.SDO_TOT_2M,   m.SDO_ENTRY_2M
  FROM LINEAS l
  JOIN MORAS m 
    ON l.CTA_CVE = m.CTA_CVE
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 5: CÁLCULO DE RATIOS DE MORA AGRUPADO
------------------------------------------------------------------------------------------------------------------------
RATIOS_MORA AS (
  SELECT
      COSECHA,
      BR_HIT_DES,
      BR_NIVEL_RIESGO,
      COUNT(*) AS Cuentas,
      SAFE_DIVIDE(SUM(SDO_ENTRY_2M), SUM(SDO_TOT_2M)) AS RATIO_MORA_ENTRY_2M,
  FROM UNIVERSO_CONSOLIDADO
  GROUP BY 1, 2, 3
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: MATRIZ PIVOTADA POR RIESGO NUMÉRICO (0 AL 5)
------------------------------------------------------------------------------------------------------------------------
SELECT 
    COSECHA,

    -- ==========================================
    -- COLUMNAS: RATIO MORA ENTRY (MOB = 2)
    -- ==========================================
    MAX(CASE WHEN BR_NIVEL_RIESGO = 0 THEN RATIO_MORA_ENTRY_2M END) AS M_ENTRY_R0,
    MAX(CASE WHEN BR_NIVEL_RIESGO = 1 THEN RATIO_MORA_ENTRY_2M END) AS M_ENTRY_R1,
    MAX(CASE WHEN BR_NIVEL_RIESGO = 2 THEN RATIO_MORA_ENTRY_2M END) AS M_ENTRY_R2,
    MAX(CASE WHEN BR_NIVEL_RIESGO = 3 THEN RATIO_MORA_ENTRY_2M END) AS M_ENTRY_R3,
    MAX(CASE WHEN BR_NIVEL_RIESGO = 4 THEN RATIO_MORA_ENTRY_2M END) AS M_ENTRY_R4,
    MAX(CASE WHEN BR_NIVEL_RIESGO = 5 THEN RATIO_MORA_ENTRY_2M END) AS M_ENTRY_R5,

FROM RATIOS_MORA

-- >>> FILTRO ÚNICO DE EXTRACCIÓN:
WHERE BR_HIT_DES = 'NOHIT'      -- Cambiar a 'NOHIT' según tu análisis de extracción

GROUP BY 1
ORDER BY COSECHA ASC;
