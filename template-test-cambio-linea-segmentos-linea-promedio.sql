/***********************************************************************************************************************
  PLANTILLA OBJETIVO: COMPARATIVA DE LÍNEAS DE CRÉDITO PROMEDIO (ACTUAL OBSERVADA VS. NUEVA HIPOTÉTICA)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES
------------------------------------------------------------------------------------------------------------------------
WITH LINEAS AS (
  SELECT
      BR_ING_TOT,              -- Ingreso total del cliente
      CTA_CVE,                 -- Clave única de la cuenta
      BR_IMP_LIM_CRED,         -- Límite de crédito asignado real (Observado en solicitud)
      BR_MODULO_SCORE_DES,     -- Descripción del módulo de score
      BR_HIT_DES,              -- Estatus de consulta en Buró (HIT / NOHIT / THIN FILE)
      SEGMENTO_SCORE,          -- Segmentación por score crediticio
      BR_NIVEL_RIESGO          -- Nivel de riesgo asignado
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2025-03-01' AND '2025-08-31'  -- <<< RANGO TEMPORAL PARA CUENTAS CON MAS DE 6 MESES DE ANTIGUEDAD
    AND BR_ORG = 210                                       -- <<< FILTRO DE PRODUCTO 
    AND CTA_CVE > 0                                        -- FILTRO CUENTAS ACTIVAS 
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: HISTÓRICO DE SALDOS MENSUALES Y MADURACIÓN (MOB).
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_NIV_MOR,       -- Nivel de mora en el mes (0 = Vigente, 1 = 1-30 días, etc.)
      a.CTA_SDO_ACT,       -- Saldo actual de la cuenta en ese corte mensual
      a.CTA_IMP_LIM_CRD,   -- Límite de crédito registrado en el mes
      b.CTA_FCH_ALTA,      -- Fecha en que se abrió la cuenta
      a.CTA_EDO_CVE,       -- Estado de la cuenta (Activa, Cancelada, etc.)
      DATE(a.ANIO, a.MES, 1) AS MES_OBS,
      
      -- Cálculo del MOB (Months On Books)
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b
    USING (CTA_CVE)
  WHERE a.TIP_INF = 210                           -- <<< FILTRO DE PRODUCTO A EVALUAR 
    AND a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2025                            -- Filtro temporal 
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: PIVOTEO DE COMPORTAMIENTO POR VENTANAS DE TIEMPO (MORAS)
------------------------------------------------------------------------------------------------------------------------
MORAS AS (
  SELECT
      CTA_CVE,
      CTA_FCH_ALTA,
      -- Si el comportamiento es del inicio (MOB <= 1) trae ese límite, si no, evalúa el máximo histórico de la cuenta
      COALESCE(
      MAX(CASE WHEN MOB <= 1 THEN CTA_IMP_LIM_CRD END), 
      MAX(CTA_IMP_LIM_CRD)) AS CTA_IMP_LIM_CRD
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1, 2
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3.5: CRUZE INTERMEDIO PARA PASAR LA REGLA DE NEGOCIO RECALCULADA CON EL LÍMITE DEL MÓDULO 3
------------------------------------------------------------------------------------------------------------------------
LINEAS_CON_NEW_LC AS (
  SELECT 
      a.BR_HIT_DES,
      b.CTA_IMP_LIM_CRD AS LC_ACTUAL, 
      CASE 
        WHEN a.BR_ING_TOT >= 4000 AND b.CTA_IMP_LIM_CRD < 4000 THEN 4000 
        ELSE b.CTA_IMP_LIM_CRD
      END AS NEW_LC
  FROM LINEAS a
  JOIN MORAS b ON a.CTA_CVE = b.CTA_CVE
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: RESUMEN COMPARATIVO DE LÍNEAS DE CRÉDITO PROMEDIO POR ESTATUS DE BURÓ
------------------------------------------------------------------------------------------------------------------------
SELECT 
    BR_HIT_DES AS SEGMENTO_BURO,
    COUNT(*) AS TOTAL_CUENTAS,
    
    -- Métricas de la línea de crédito real observada
    ROUND(AVG(LC_ACTUAL), 2) AS LINEA_PROMEDIO_ACTUAL,
    ROUND(MIN(LC_ACTUAL), 2) AS LINEA_MINIMA_ACTUAL,
    ROUND(MAX(LC_ACTUAL), 2) AS LINEA_MAXIMA_ACTUAL,
    
    -- Métricas de la línea de crédito nueva recalculada (Post-Aumento)
    ROUND(AVG(NEW_LC), 2) AS LINEA_PROMEDIO_NUEVA,
    ROUND(MIN(NEW_LC), 2) AS LINEA_MINIMA_NUEVA,
    ROUND(MAX(NEW_LC), 2) AS LINEA_MAXIMA_NUEVA
FROM LINEAS_CON_NEW_LC
WHERE BR_HIT_DES IN ('HIT', 'NOHIT') -- Excluye Thin File si solo requieres estos dos segmentos
GROUP BY 1
ORDER BY 1;
