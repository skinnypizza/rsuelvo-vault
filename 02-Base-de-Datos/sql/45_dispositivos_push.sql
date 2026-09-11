-- ============================================================
-- RSUELVO v2 :: MIGRACIÓN 45 (2026-09-11)
-- Dispositivos push FCM por usuario (base notificaciones de reserva)
-- ============================================================
-- Diseño de Codex (Fase 1, docs/push-inventario-fase-1.md), aplicado por
-- orquestador + triggers de proyecto (updated_at/auditoría).
-- El registro lo hará la app vía Edge Function con JWT (dueño desde auth.uid);
-- RLS solo-propios; sin service_role en Flutter. Emisor + FCM en Fase 2
-- (requiere proyecto Firebase, google-services.json y secreto service account).

-- == TABLAS ==
CREATE TABLE IF NOT EXISTS rsuelvo.tbl_dispositivos_push (
  id_dispositivo uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  id_usuario uuid NOT NULL REFERENCES rsuelvo.tbl_usuarios(id_usuario) ON DELETE CASCADE,
  token_fcm text NOT NULL UNIQUE,
  plataforma text NOT NULL CHECK (plataforma IN ('ANDROID','IOS')),
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dispositivos_push_usuario_activo
  ON rsuelvo.tbl_dispositivos_push (id_usuario) WHERE activo;
ALTER TABLE rsuelvo.tbl_dispositivos_push ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON rsuelvo.tbl_dispositivos_push TO authenticated;
GRANT ALL ON rsuelvo.tbl_dispositivos_push TO service_role;

-- == TRIGGERS ==
CREATE TRIGGER trg_dispositivos_push_updated_at BEFORE UPDATE ON rsuelvo.tbl_dispositivos_push
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_set_updated_at();
CREATE TRIGGER trg_audit_dispositivos_push AFTER INSERT OR UPDATE OR DELETE ON rsuelvo.tbl_dispositivos_push
  FOR EACH ROW EXECUTE FUNCTION rsuelvo.fn_auditar_cambio();

-- == RLS ==
DROP POLICY IF EXISTS dispositivos_push_select_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_select_propios ON rsuelvo.tbl_dispositivos_push FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));
DROP POLICY IF EXISTS dispositivos_push_update_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_update_propios ON rsuelvo.tbl_dispositivos_push FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));
DROP POLICY IF EXISTS dispositivos_push_insert_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_insert_propios ON rsuelvo.tbl_dispositivos_push FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));
DROP POLICY IF EXISTS dispositivos_push_delete_propios ON rsuelvo.tbl_dispositivos_push;
CREATE POLICY dispositivos_push_delete_propios ON rsuelvo.tbl_dispositivos_push FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM rsuelvo.tbl_usuarios u WHERE u.id_usuario=tbl_dispositivos_push.id_usuario AND u.auth_user_id=auth.uid()));
