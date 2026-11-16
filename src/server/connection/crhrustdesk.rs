use super::*;

impl Connection {
    pub(super) async fn authorize_crhrustdesk_account(&mut self) -> bool {
        if !self.stream.is_secured() {
            self.send_login_error("Central account access requires an encrypted connection")
                .await;
            return false;
        }
        let scope = match crate::crhrustdesk::permit_scope(&self.lr) {
            Some(scope) => scope,
            None => {
                self.send_login_error("Central account access does not support this session type")
                    .await;
                return false;
            }
        };
        let name = match crate::crhrustdesk::verify_permit(
            &self.lr.crhrustdesk_permit,
            &self.hash.crhrustdesk_nonce,
            &self.lr.my_id,
            scope,
        ) {
            Ok(name) => name,
            Err(_) => {
                self.send_login_error("Central account authorization was rejected")
                    .await;
                return false;
            }
        };
        self.lr.crhrustdesk_permit.clear();
        self.lr.my_name = name.clone();
        self.set_conn_audit_primary_auth(ConnAuditPrimaryAuth::CentralAccount);
        if !self.send_logon_response_and_keep_alive().await {
            return false;
        }
        self.try_start_cm(self.lr.my_id.clone(), name, self.authorized);
        true
    }
}
