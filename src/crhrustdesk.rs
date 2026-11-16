pub(crate) fn initialize() {
    use base::config::keys;
    use hbb_common::config;

    *config::APP_NAME.write().unwrap() = "CrhRustDesk".to_owned();
    let mut defaults = config::DEFAULT_SETTINGS.write().unwrap();
    for (key, value) in [
        (
            keys::OPTION_CUSTOM_RENDEZVOUS_SERVER,
            option_env!("CRHRUSTDESK_ID_SERVER").unwrap_or("127.0.0.1"),
        ),
        (
            keys::OPTION_RELAY_SERVER,
            option_env!("CRHRUSTDESK_RELAY_SERVER").unwrap_or("127.0.0.1:21117"),
        ),
        (
            keys::OPTION_API_SERVER,
            option_env!("CRHRUSTDESK_API_SERVER").unwrap_or("http://127.0.0.1:21114"),
        ),
        (keys::OPTION_KEY, env!("CRHRUSTDESK_SERVER_KEY")),
        (keys::OPTION_DIRECT_SERVER, "Y"),
        (keys::OPTION_APPROVE_MODE, "click"),
    ] {
        defaults.insert(key.to_owned(), value.to_owned());
    }
    #[cfg(windows)]
    role::apply();
}

#[cfg(any(windows, test))]
mod role;

#[cfg(windows)]
pub(crate) mod update;

pub(crate) fn requires_account_permit() -> bool {
    hbb_common::config::HARD_SETTINGS.read().unwrap()
        .get("crhrustdesk-role").map_or(false, |role| role == "incoming")
}

use base::message_proto::{login_request, message, Hash, LoginRequest, Message, PublicKey};
use hbb_common::{
    anyhow::{anyhow, bail},
    config::{Config, LocalConfig},
    protobuf::Message as _,
    rendezvous_proto::IdPk,
    sodiumoxide::{base64, crypto::sign, randombytes},
    tokio::time::{timeout, Duration},
    ResultType, Stream,
};

pub(crate) fn local_ipv4() -> String {
    let mut addresses: Vec<_> = default_net::get_interfaces()
        .into_iter()
        .filter(|interface| interface.is_up())
        .flat_map(|interface| interface.ipv4)
        .map(|network| network.addr)
        .filter(|ip| {
            !ip.is_loopback() && !ip.is_unspecified() && !ip.is_link_local() && !ip.is_multicast()
        })
        .collect();
    addresses.sort_unstable();
    addresses.dedup();
    addresses
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(", ")
}

pub(crate) fn prepare_hash(hash: &mut Hash) {
    hash.crhrustdesk_device_id = Config::get_id();
    hash.crhrustdesk_nonce = randombytes::randombytes(32)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
}

fn endpoint(path: &str) -> ResultType<String> {
    let api = Config::get_option("api-server");
    let url = reqwest::Url::parse(&api)?;
    if url.scheme() == "http" && matches!(url.host_str(), Some("127.0.0.1") | Some("localhost")) {
        return Ok(format!("http://127.0.0.1:21120/crhrustdesk/{path}"));
    }
    if url.scheme() != "https" || !url.username().is_empty() || url.password().is_some() {
        bail!("CrhRustDesk account access requires a trusted HTTPS API");
    }
    Ok(format!("{}/crhrustdesk/{path}", api.trim_end_matches('/')))
}

async fn account_request(path: &str, body: serde_json::Value) -> ResultType<reqwest::Response> {
    let token = LocalConfig::get_option("access_token");
    if token.is_empty() {
        bail!("Sign in to your CrhRustDesk account before connecting by IP");
    }
    let client = reqwest::Client::builder()
        .use_native_tls()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(8))
        .build()?;
    Ok(client
        .post(endpoint(path)?)
        .bearer_auth(token)
        .json(&body)
        .send()
        .await?)
}

pub(crate) async fn connect_direct(address: &str) -> ResultType<(Stream, Vec<u8>)> {
    let mut stream = hbb_common::socket_client::connect_tcp_local(
        crate::check_port(address, 21118),
        None,
        hbb_common::config::CONNECT_TIMEOUT,
    )
    .await?;
    stream.set_max_packet_length(16384);
    let bytes = timeout(Duration::from_secs(8), stream.next())
        .await?
        .ok_or_else(|| anyhow!("CrhRustDesk direct identity was not received"))??;
    let msg = Message::parse_from_bytes(&bytes)?;
    let signed = match msg.union {
        Some(message::Union::SignedId(value)) if value.id.len() > sign::SIGNATUREBYTES => value.id,
        _ => {
            bail!("The target must run the new CrhRustDesk client with encrypted Direct IP enabled")
        }
    };
    let hint = IdPk::parse_from_bytes(&signed[sign::SIGNATUREBYTES..])?;
    let response = account_request("identity", serde_json::json!({"target": hint.id}))
        .await?
        .error_for_status()?;
    #[derive(serde_derive::Deserialize)]
    struct Identity {
        id: String,
        public_key: String,
    }
    let identity: Identity = response.json().await?;
    let public_key = base64::decode(&identity.public_key, base64::Variant::Original)
        .map_err(|_| anyhow!("Invalid registered device key encoding"))?;
    let key = sign::PublicKey::from_slice(&public_key)
        .ok_or_else(|| anyhow!("Invalid registered device key"))?;
    let (id, remote_key, _, advertised) = crate::common::decode_id_pk_dtls(&signed, &key)?;
    if id != identity.id || id != hint.id {
        bail!("Direct IP device identity does not match the registered device");
    }
    let (asymmetric_value, symmetric_value, secret) =
        crate::common::create_symmetric_key_msg(remote_key);
    let picked = hbb_common::tcp::kx_version_for(advertised);
    let mut reply = Message::new();
    reply.set_public_key(PublicKey {
        asymmetric_value: asymmetric_value.clone(),
        symmetric_value,
        kx_version: picked,
        ..Default::default()
    });
    stream.send(&reply).await?;
    stream.set_negotiated_key(
        secret,
        true,
        &hbb_common::tcp::KxTranscript {
            initiator_pk: &asymmetric_value,
            responder_pk: &remote_key,
            advertised,
            picked,
        },
    )?;
    stream.set_max_packet_length(usize::MAX);
    Ok((stream, public_key))
}

pub(crate) fn permit_scope(lr: &LoginRequest) -> Option<&'static str> {
    match lr.union.as_ref() {
        None => Some("desktop"),
        Some(login_request::Union::FileTransfer(_)) => Some("file_transfer"),
        _ => None,
    }
}

pub(crate) async fn attach_permit(
    msg: &mut Message,
    hash: &Hash,
    peer_key: &[u8],
    encrypted: bool,
) -> ResultType<()> {
    if !encrypted
        || peer_key.len() != 32
        || hash.crhrustdesk_nonce.is_empty()
        || LocalConfig::get_option("access_token").is_empty()
    {
        return Ok(());
    }
    if let Some(message::Union::LoginRequest(lr)) = msg.union.as_mut() {
        let scope = match permit_scope(lr) {
            Some(scope) => scope,
            None => return Ok(()),
        };
        let response = account_request(
            "permit",
            serde_json::json!({
                "target": hash.crhrustdesk_device_id,
                "nonce": hash.crhrustdesk_nonce,
                "controller": lr.my_id,
                "scope": scope,
            }),
        )
        .await?;
        if response.status() == reqwest::StatusCode::FORBIDDEN {
            return Ok(());
        }
        #[derive(serde_derive::Deserialize)]
        struct Response {
            permit: String,
        }
        let result: Response = response.error_for_status()?.json().await?;
        let proof = base64::decode(&result.permit, base64::Variant::Original)
            .map_err(|_| anyhow!("Invalid session permit encoding"))?;
        verify_signed_permit(
            &proof,
            permit_public_key(),
            &hash.crhrustdesk_device_id,
            &hash.crhrustdesk_nonce,
            &lr.my_id,
            peer_key,
            unix_time()?,
            scope,
        )?;
        lr.crhrustdesk_permit = proof.into();
    }
    Ok(())
}

#[derive(serde_derive::Deserialize)]
struct Permit {
    domain: String,
    name: String,
    target: String,
    controller: String,
    nonce: String,
    scope: String,
    expires: u64,
    target_public_key: String,
}

fn verify_signed_permit(
    proof: &[u8],
    public_key: &str,
    target: &str,
    nonce: &str,
    controller: &str,
    peer_key: &[u8],
    now: u64,
    scope: &str,
) -> ResultType<String> {
    if proof.len() > 4096 || nonce.len() != 64 {
        bail!("Invalid session permit");
    }
    let key = base64::decode(public_key, base64::Variant::Original)
        .map_err(|_| anyhow!("Invalid permit verification key encoding"))?;
    let key = sign::PublicKey::from_slice(&key)
        .ok_or_else(|| anyhow!("Invalid permit verification key"))?;
    let payload =
        sign::verify(proof, &key).map_err(|_| anyhow!("Invalid session permit signature"))?;
    let permit: Permit = serde_json::from_slice(&payload)?;
    let target_key = base64::decode(&permit.target_public_key, base64::Variant::Original)
        .map_err(|_| anyhow!("Invalid permit device key"))?;
    if permit.domain != "crhrustdesk-desktop-v1"
        || permit.target != target
        || permit.nonce != nonce
        || permit.controller != controller
        || permit.scope != scope
        || permit.expires <= now
        || permit.expires > now.saturating_add(60)
        || target_key != peer_key
        || peer_key.len() != 32
        || permit.name.is_empty()
        || permit.name.len() > 128
    {
        bail!("Session permit is expired or does not match this connection");
    }
    Ok(permit.name)
}

pub(crate) fn verify_permit(proof: &[u8], nonce: &str, controller: &str, scope: &str) -> ResultType<String> {
    verify_signed_permit(
        proof,
        permit_public_key(),
        &Config::get_id(),
        nonce,
        controller,
        &Config::get_key_pair().1,
        unix_time()?,
        scope,
    )
}

fn permit_public_key() -> &'static str {
    option_env!("CRHRUSTDESK_PERMIT_PUBLIC_KEY").unwrap_or("")
}

fn unix_time() -> ResultType<u64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ticket() -> (serde_json::Value, sign::PublicKey, sign::SecretKey) {
        let (pk, sk) = sign::gen_keypair();
        (
            serde_json::json!({
                "domain": "crhrustdesk-desktop-v1", "name": "test_operator",
                "target": "123456789", "controller": "987654321",
                "nonce": "ab".repeat(32), "scope": "desktop", "expires": 1060,
                "target_public_key": base64::encode([42u8; 32], base64::Variant::Original),
            }),
            pk,
            sk,
        )
    }

    fn verify(
        value: &serde_json::Value,
        pk: &sign::PublicKey,
        sk: &sign::SecretKey,
    ) -> ResultType<String> {
        verify_signed_permit(
            &sign::sign(&serde_json::to_vec(value)?, sk),
            &base64::encode(pk.0, base64::Variant::Original),
            "123456789",
            &"ab".repeat(32),
            "987654321",
            &[42u8; 32],
            1000,
            "desktop",
        )
    }

    #[test]
    fn authorized_account_permit_is_accepted() {
        let (value, pk, sk) = ticket();
        assert_eq!(verify(&value, &pk, &sk).unwrap(), "test_operator");
    }

    #[test]
    fn permits_cannot_cross_connection_device_or_scope() {
        let (value, pk, sk) = ticket();
        for (field, replacement) in [
            ("target", serde_json::json!("222222222")),
            ("controller", serde_json::json!("111111111")),
            ("nonce", serde_json::json!("cd".repeat(32))),
            ("scope", serde_json::json!("terminal")),
            ("domain", serde_json::json!("another-product")),
            ("expires", serde_json::json!(999)),
            ("expires", serde_json::json!(1061)),
            (
                "target_public_key",
                serde_json::json!(base64::encode([43u8; 32], base64::Variant::Original)),
            ),
        ] {
            let mut altered = value.clone();
            altered[field] = replacement;
            assert!(
                verify(&altered, &pk, &sk).is_err(),
                "{field} must be checked"
            );
        }
    }

    #[test]
    fn tampered_signature_is_rejected() {
        let (value, pk, sk) = ticket();
        let mut proof = sign::sign(&serde_json::to_vec(&value).unwrap(), &sk);
        proof[0] ^= 1;
        assert!(verify_signed_permit(
            &proof,
            &base64::encode(pk.0, base64::Variant::Original),
            "123456789",
            &"ab".repeat(32),
            "987654321",
            &[42u8; 32],
            1000,
            "desktop",
        )
        .is_err());
    }

    #[test]
    fn permits_cannot_cross_desktop_and_file_transfer_sessions() {
        let (mut value, pk, sk) = ticket();
        for (scope, other) in [("desktop", "file_transfer"), ("file_transfer", "desktop")] {
            value["scope"] = serde_json::json!(scope);
            let proof = sign::sign(&serde_json::to_vec(&value).unwrap(), &sk);
            let verify_scope = |expected| verify_signed_permit(
                &proof, &base64::encode(pk.0, base64::Variant::Original),
                "123456789", &"ab".repeat(32), "987654321", &[42u8; 32], 1000, expected,
            );
            assert_eq!(verify_scope(scope).unwrap(), "test_operator");
            assert!(verify_scope(other).is_err());
        }
    }

    #[test]
    fn login_type_selects_only_desktop_or_file_transfer_permits() {
        let mut lr = LoginRequest::new();
        assert_eq!(permit_scope(&lr), Some("desktop"));
        lr.set_file_transfer(Default::default());
        assert_eq!(permit_scope(&lr), Some("file_transfer"));
        lr.set_port_forward(Default::default());
        assert_eq!(permit_scope(&lr), None);
    }
}
