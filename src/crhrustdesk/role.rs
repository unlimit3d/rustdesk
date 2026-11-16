#[derive(Clone, Copy, Debug, PartialEq)]
enum Role {
    Endpoint,
    Operator,
}

#[derive(serde_derive::Deserialize)]
struct Profile {
    role: String,
    id_server: String,
    relay_server: String,
    api_server: String,
    key: String,
}

fn parse(value: &str) -> Option<Role> {
    match value.trim() {
        "incoming" => Some(Role::Endpoint),
        "outgoing" => Some(Role::Operator),
        _ => None,
    }
}

#[cfg(windows)]
pub(super) fn apply() {
    use hbb_common::{config, log};
    let result = std::env::current_exe().and_then(|exe| {
        let directory = exe.parent().ok_or_else(|| std::io::Error::new(
            std::io::ErrorKind::InvalidInput, "Executable directory is missing"))?;
        std::fs::read_to_string(directory.join("connection-profile.json"))
    });
    let profile = match result {
        Ok(value) => match serde_json::from_str::<Profile>(&value) {
            Ok(profile) => Some(profile),
            Err(error) => {
                log::error!("Invalid CrhRustDesk installation profile: {error}; restricting this client to incoming access");
                None
            }
        },
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return,
        Err(error) => {
            log::error!("Cannot read CrhRustDesk installation role: {error}; restricting this client to incoming access");
            None
        }
    };
    let role = match profile.as_ref().and_then(|profile| parse(&profile.role)) {
        Some(role) => role,
        None => {
            if profile.is_some() { log::error!("Invalid CrhRustDesk installation role; restricting this client to incoming access"); }
            Role::Endpoint
        }
    };
    let value = match role { Role::Endpoint => "incoming", Role::Operator => "outgoing" };
    let mut settings = config::HARD_SETTINGS.write().unwrap();
    settings.insert("conn-type".to_owned(), value.to_owned());
    settings.insert("crhrustdesk-role".to_owned(), value.to_owned());
    drop(settings);
    if let Some(profile) = profile {
        let mut options = config::OVERWRITE_SETTINGS.write().unwrap();
        for (key, value) in [
            ("custom-rendezvous-server", profile.id_server),
            ("relay-server", profile.relay_server),
            ("api-server", profile.api_server),
            ("key", profile.key),
            ("direct-server", if role == Role::Endpoint { "Y" } else { "N" }.to_owned()),
            ("direct-access-port", "21118".to_owned()),
            ("approve-mode", "click".to_owned()),
            ("allow-hide-cm", "N".to_owned()),
        ] {
            options.insert(key.to_owned(), value);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn installer_roles_select_existing_connection_modes() {
        assert_eq!(parse("incoming\r\n"), Some(Role::Endpoint));
        assert_eq!(parse("outgoing"), Some(Role::Operator));
    }

    #[test]
    fn unknown_role_does_not_grant_operator_mode() {
        assert_eq!(parse("admin"), None);
    }
}
