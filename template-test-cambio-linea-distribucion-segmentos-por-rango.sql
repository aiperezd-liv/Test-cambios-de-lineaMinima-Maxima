/***********************************************************************************************************************
  PERFILAMIENTO DE PORTAFOLIO: DISTRIBUCIÓN PORCENTUAL DE CUENTAS POR RANGO DE LÍNEA DE CRÉDITO (CORREGIDO Y HOMOLOGADO)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: HISTÓRICO MENSUAL (RECONSTRUCCIÓN DE LÍNEA DE CRÉDITO BASE POR CUENTA ÚNICA)
------------------------------------------------------------------------------------------------------------------------
WITH SDO_CONSOLIDADO AS (
  SELECT 
      a.CTA_CVE,
      -- Primero se procesa el ajuste estricto de la línea de crédito para cada cuenta única
      COALESCE(
        MAX(CASE WHEN DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) <= 1 THEN a.CTA_IMP_LIM_CRD END), 
        MAX(a.CTA_IMP_LIM_CRD)
      ) AS CTA_IMP_LIM_CRD
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b
    USING (CTA_CVE)
  WHERE a.TIP_INF = 210
    AND a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2025
  GROUP BY 1
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: UNIVERSO DE CUENTAS Y ASIGNACIÓN DE SU RANGO (DESPUÉS DEL AJUSTE DE LÍNEA)
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_LINEAS AS (
  SELECT
      a.CTA_CVE,
      a.BR_HIT_DES,
      a.BR_ING_TOT,
      b.CTA_IMP_LIM_CRD,
      
      -- Ahora la asignación del rango se lee sobre el límite de crédito ya homogenizado
      CASE 
        WHEN a.BR_ING_TOT >= 4000 AND b.CTA_IMP_LIM_CRD < 4000 THEN 'a. Mínima Target (Ing>=4k | LC<4k)'
        WHEN b.CTA_IMP_LIM_CRD < 4000                          THEN 'b. [Mínima, 4000) General'
        WHEN b.CTA_IMP_LIM_CRD >= 4000  AND b.CTA_IMP_LIM_CRD < 6000  THEN 'c. [4000, 6000)'
        WHEN b.CTA_IMP_LIM_CRD >= 6000  AND b.CTA_IMP_LIM_CRD < 8000  THEN 'd. [6000, 8000)'
        WHEN b.CTA_IMP_LIM_CRD >= 8000  AND b.CTA_IMP_LIM_CRD < 10000 THEN 'e. [8000, 10000)'
        WHEN b.CTA_IMP_LIM_CRD >= 10000 AND b.CTA_IMP_LIM_CRD < 15000 THEN 'f. [10000, 15000)'
        WHEN b.CTA_IMP_LIM_CRD >= 15000 AND b.CTA_IMP_LIM_CRD < 20000 THEN 'g. [15000, 20000)'
        WHEN b.CTA_IMP_LIM_CRD >= 20000                               THEN 'h. [20000, o más)'
        ELSE 'i. Otros / Fuera de Rango'
      END AS RANGO_LINEA
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES` a
  JOIN SDO_CONSOLIDADO b 
    ON a.CTA_CVE = b.CTA_CVE
  WHERE a.DT_FCH_SOL BETWEEN '2025-03-01' AND '2025-08-31'
    AND a.BR_ORG = 210
    AND a.CTA_CVE > 0
    AND a.BR_HIT_DES IN ('HIT', 'NOHIT')
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: CONTEO ABSOLUTO DE CUENTAS POR RANGO Y TIPO DE BURÓ
------------------------------------------------------------------------------------------------------------------------
CONTEOS AS (
  SELECT 
    RANGO_LINEA,
    COUNT(CASE WHEN BR_HIT_DES = 'HIT' THEN 1 END) AS CUENTAS_HIT,
    COUNT(CASE WHEN BR_HIT_DES = 'NOHIT' THEN 1 END) AS CUENTAS_NOHIT,
    COUNT(*) AS CUENTAS_TOTALES
  FROM UNIVERSO_LINEAS
  GROUP BY 1
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: TOTALIZADORES VERTICALES PARA EL CÁLCULO DEL % (DENOMINADORES)
------------------------------------------------------------------------------------------------------------------------
TOTALES_UNIVERSO AS (
  SELECT 
    SUM(CUENTAS_HIT) AS GRAN_TOTAL_HIT,
    SUM(CUENTAS_NOHIT) AS GRAN_TOTAL_NOHIT,
    SUM(CUENTAS_TOTALES) AS GRAN_TOTAL_GENERAL
  FROM CONTEOS
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: MATRIZ DE DISTRIBUCIÓN PORCENTUAL VERTICAL
------------------------------------------------------------------------------------------------------------------------
SELECT 
  c.RANGO_LINEA,
  
  -- Volúmenes Absolutos (Coincidirán exactamente uno a uno con el reporte de activación)
  c.CUENTAS_HIT,
  c.CUENTAS_NOHIT,
  c.CUENTAS_TOTALES AS TOTAL_COMBINADO,

  -- Distribución Porcentual Vertical
  SAFE_DIVIDE(c.CUENTAS_HIT, t.GRAN_TOTAL_HIT) AS PORC_DIST_HIT,
  SAFE_DIVIDE(c.CUENTAS_NOHIT, t.GRAN_TOTAL_NOHIT) AS PORC_DIST_NOHIT,
  SAFE_DIVIDE(c.CUENTAS_TOTALES, t.GRAN_TOTAL_GENERAL) AS PORC_DIST_TOTAL_GENERAL
FROM CONTEOS c
CROSS JOIN TOTALES_UNIVERSO t
ORDER BY c.RANGO_LINEA;
