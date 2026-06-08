/***********************************************************************************************************************
  PERFILAMIENTO DE PORTAFOLIO: RATIO DE ACTIVACIÓN POR RANGO DE LÍNEA DE CRÉDITO (ABS SOLO EN IND_ACTIVACION)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES (UNIVERSO BASE)
------------------------------------------------------------------------------------------------------------------------
WITH LINEAS AS (
  SELECT
      CTA_CVE,
      BR_HIT_DES,
      BR_ING_TOT
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2025-03-01' AND '2025-08-31'
    AND BR_ORG = 210
    AND CTA_CVE > 0
    AND BR_HIT_DES IN ('HIT', 'NOHIT')
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: HISTÓRICO MENSUAL Y RECOPILACIÓN DE FECHAS (ALTA Y PRIMERA COMPRA)
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_IMP_LIM_CRD,
      b.CTA_FCH_ALTA,
      MAX(a.CTA_FCH_PRM_CMP) AS CTA_FCH_PRM_CMP, 
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b
    USING (CTA_CVE)
  WHERE a.TIP_INF = 210
    AND a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2025
  GROUP BY 1, 2, 3, a.ANIO, a.MES
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: DETALLE DE CUENTAS (RECONSTRUCCIÓN DE LÍNEA MÁXIMA Y EVALUACIÓN DE ACTIVACIÓN CON ABS)
------------------------------------------------------------------------------------------------------------------------
DETALLE_CUENTAS AS (
  SELECT
      CTA_CVE,
      CTA_FCH_ALTA,
      COALESCE(
        MAX(CASE WHEN MOB <= 1 THEN CTA_IMP_LIM_CRD END), 
        MAX(CTA_IMP_LIM_CRD)
      ) AS CTA_IMP_LIM_CRD,
      
      -- El valor absoluto (ABS) se aplica exclusivamente aquí para mitigar diferencias de fechas negativas
      MAX(CASE 
        WHEN CTA_FCH_PRM_CMP IS NOT NULL 
         AND ABS(DATE_DIFF(DATE(CTA_FCH_PRM_CMP), DATE(CTA_FCH_ALTA), MONTH)) <= 3 THEN 1 
        ELSE 0 
      END) AS IND_ACTIVACION_3M
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1, 2
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: ASIGNACIÓN DE MATRIZ DE RANGOS DE LÍNEA DE CRÉDITO
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_RANGOS AS (
  SELECT
      l.CTA_CVE,
      l.BR_HIT_DES,
      d.IND_ACTIVACION_3M,
      CASE 
        WHEN l.BR_ING_TOT >= 4000 AND d.CTA_IMP_LIM_CRD < 4000 THEN 'a. Mínima Target (Ing>=4k | LC<4k)'
        WHEN d.CTA_IMP_LIM_CRD < 4000                          THEN 'b. [Mínima, 4000) General'
        WHEN d.CTA_IMP_LIM_CRD >= 4000  AND d.CTA_IMP_LIM_CRD < 6000  THEN 'c. [4000, 6000)'
        WHEN d.CTA_IMP_LIM_CRD >= 6000  AND d.CTA_IMP_LIM_CRD < 8000  THEN 'd. [6000, 8000)'
        WHEN d.CTA_IMP_LIM_CRD >= 8000  AND d.CTA_IMP_LIM_CRD < 10000 THEN 'e. [8000, 10000)'
        WHEN d.CTA_IMP_LIM_CRD >= 10000 AND d.CTA_IMP_LIM_CRD < 15000 THEN 'f. [10000, 15000)'
        WHEN d.CTA_IMP_LIM_CRD >= 15000 AND d.CTA_IMP_LIM_CRD < 20000 THEN 'g. [15000, 20000)'
        WHEN d.CTA_IMP_LIM_CRD >= 20000                               THEN 'h. [20000, o más)'
        ELSE 'i. Otros / Fuera de Rango'
      END AS RANGO_LINEA
  FROM LINEAS l
  JOIN DETALLE_CUENTAS d 
    ON l.CTA_CVE = d.CTA_CVE
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: MATRIZ DE PORCENTAJES DE ACTIVACIÓN (% CUENTAS CON COMPRA EN LOS PRIMEROS 3 MESES)
------------------------------------------------------------------------------------------------------------------------
SELECT 
  RANGO_LINEA,
  
  COUNT(CASE WHEN BR_HIT_DES = 'HIT' THEN 1 END) AS TOTAL_CUENTAS_HIT,
  COUNT(CASE WHEN BR_HIT_DES = 'NOHIT' THEN 1 END) AS TOTAL_CUENTAS_NOHIT,

  SAFE_DIVIDE(SUM(CASE WHEN BR_HIT_DES = 'HIT' THEN IND_ACTIVACION_3M ELSE 0 END), 
              COUNT(CASE WHEN BR_HIT_DES = 'HIT' THEN 1 END)) AS PORC_ACTIVACION_HIT_3M,
              
  SAFE_DIVIDE(SUM(CASE WHEN BR_HIT_DES = 'NOHIT' THEN IND_ACTIVACION_3M ELSE 0 END), 
              COUNT(CASE WHEN BR_HIT_DES = 'NOHIT' THEN 1 END)) AS PORC_ACTIVACION_NOHIT_3M,

  SAFE_DIVIDE(SUM(IND_ACTIVACION_3M), COUNT(*)) AS PORC_ACTIVACION_TOTAL_GENERAL
FROM UNIVERSO_RANGOS
GROUP BY 1
ORDER BY RANGO_LINEA;
