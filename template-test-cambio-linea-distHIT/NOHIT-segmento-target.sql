/***********************************************************************************************************************
  PERFILAMIENTO DE PORTAFOLIO: DISTRIBUCIÓN DE NIVELES DE RIESGO DENTRO DE CADA RANGO DE LÍNEA DE CRÉDITO
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: HISTÓRICO MENSUAL (RECONSTRUCCIÓN DE LÍNEA DE CRÉDITO BASE POR CUENTA ÚNICA)
------------------------------------------------------------------------------------------------------------------------
WITH SDO_CONSOLIDADO AS (
  SELECT 
      a.CTA_CVE,
      -- Ajuste estricto de la línea de crédito para cada cuenta única (Tomado de tu segunda plantilla base)
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
-- MÓDULO 2: UNIVERSO DE CUENTAS, ASIGNACIÓN DE SU RANGO DE LÍNEA Y FILTRO INICIAL BURÓ
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_LINEAS AS (
  SELECT
      a.CTA_CVE,
      a.BR_HIT_DES,
      a.BR_ING_TOT,
      a.BR_NIVEL_RIESGO,
      b.CTA_IMP_LIM_CRD,
      
      -- Clasificación exacta solicitada por Rango de Línea de Crédito
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
    AND a.BR_HIT_DES IN ('HIT', 'NOHIT') -- Consideramos ambos universos para segmentar después
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: AGREGACIÓN DE VOLÚMENES ABSOLUTOS (CONTEOS)
------------------------------------------------------------------------------------------------------------------------
CONTEOS_BASE AS (
  SELECT 
      BR_HIT_DES,
      RANGO_LINEA,
      BR_NIVEL_RIESGO,
      COUNT(*) AS CUENTAS_POR_RIESGO
  FROM UNIVERSO_LINEAS
  where BR_NIVEL_RIESGO IS NOT NULL 
  GROUP BY 1, 2, 3
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: CÁLCULO ANALÍTICO DE DISTRIBUCIÓN PORCENTUAL (SUMA 100% POR CADA RANGO_LINEA)
------------------------------------------------------------------------------------------------------------------------
MATRIZ_FINAL AS (
  SELECT 
      BR_HIT_DES,
      RANGO_LINEA,
      BR_NIVEL_RIESGO,
      CUENTAS_POR_RIESGO,
      
      -- Obtiene la suma total de cuentas pertenecientes EXCLUSIVAMENTE a este rango de línea y este tipo de buró
      SUM(CUENTAS_POR_RIESGO) OVER(PARTITION BY BR_HIT_DES, RANGO_LINEA) AS TOTAL_CUENTAS_RANGO,
      
      -- Divide el volumen del nivel de riesgo sobre el total de su respectivo rango de línea
      SAFE_DIVIDE(CUENTAS_POR_RIESGO, SUM(CUENTAS_POR_RIESGO) OVER(PARTITION BY BR_HIT_DES, RANGO_LINEA)) AS PORC_DIST_RANGO_RIESGO
  FROM CONTEOS_BASE
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: REPORTE CON FILTRO EXTRACTOR POR TIPO DE BURÓ
------------------------------------------------------------------------------------------------------------------------
SELECT 
    RANGO_LINEA,
    BR_NIVEL_RIESGO,
    CUENTAS_POR_RIESGO,
    TOTAL_CUENTAS_RANGO,
    PORC_DIST_RANGO_RIESGO
FROM MATRIZ_FINAL

-- >>> FILTRO DE EXTRACCIÓN (Modificar aquí según lo que requieras ver):
WHERE BR_HIT_DES = 'NOHIT'      -- Cambiar a 'NOHIT' para extraer el otro comportamiento

ORDER BY RANGO_LINEA, BR_NIVEL_RIESGO;
