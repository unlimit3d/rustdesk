use hbb_common::{
    anyhow::anyhow,
    config::{self, Config, LocalConfig},
    sha2::{Digest, Sha256},
    sodiumoxide::{base64, crypto::sign},
    ResultType,
};
use std::{sync::Once, time::Duration};

pub(crate) fn start() {
    if !crate::platform::is_installed() || (config::is_outgoing_only() == crate::is_server()) {
        return;
    }
    let installed = std::path::PathBuf::from(crate::platform::get_install_info().3).canonicalize();
    let current = std::env::current_exe().and_then(|path| path.canonicalize());
    match (current, installed) {
        (Ok(current), Ok(installed)) if current == installed => {}
        (Ok(_), Ok(_)) => return,
        (Err(error), _) | (_, Err(error)) => {
            hbb_common::log::warn!("Cannot verify inventory installation path: {error}");
            return;
        }
    }
    static START: Once = Once::new();
    START.call_once(|| {
        if let Err(error) = std::thread::Builder::new()
            .name("client-inventory".to_owned())
            .spawn(|| loop {
                if let Err(error) = report() {
                    hbb_common::throttled_log!(
                        Duration::from_secs(300),
                        warn,
                        "Client inventory report failed: {error}"
                    );
                }
                std::thread::sleep(Duration::from_secs(60));
            })
        {
            hbb_common::log::warn!("Cannot start client inventory: {error}");
        }
    });
}

fn report() -> ResultType<()> {
    let token = LocalConfig::get_option("access_token");
    let machine = hbb_common::get_uuid();
    if machine.is_empty() {
        return Err(anyhow!("Machine identity is unavailable"));
    }
    let executable = std::env::current_exe()?;
    let directory = executable
        .parent()
        .ok_or_else(|| anyhow!("Missing executable directory"))?;
    let release: serde_json::Value =
        serde_json::from_slice(&std::fs::read(directory.join("client-release.json"))?)?;
    let role = if config::is_outgoing_only() {
        "outgoing"
    } else {
        "incoming"
    };
    let payload = serde_json::to_vec(&serde_json::json!({
        "domain": "crhrustdesk-inventory-v1",
        "machine_id": format!("{:x}", Sha256::digest(&machine)),
        "id": Config::get_id(),
        "hostname": crate::common::hostname(),
        "role": role,
        "version": crate::VERSION,
        "revision": release["revision"].as_u64().ok_or_else(|| anyhow!("Missing release revision"))?,
        "reported_at": super::unix_time()?,
    }))?;
    let (secret, public) = Config::get_key_pair();
    let secret = sign::SecretKey::from_slice(&secret)
        .ok_or_else(|| anyhow!("Missing device signing key"))?;
    let client = reqwest::blocking::Client::builder()
        .use_native_tls()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(8))
        .build()?;
    client
        .post(super::endpoint("inventory")?)
        .bearer_auth(token)
        .json(&serde_json::json!({
            "public_key": base64::encode(public, base64::Variant::Original),
            "report": base64::encode(sign::sign(&payload, &secret), base64::Variant::Original),
        }))
        .send()?
        .error_for_status()?;
    Ok(())
}
