pub(crate) const IDLE_QUERY: &str = "crhrustdesk-update-ready";

pub(crate) fn check_available() -> hbb_common::ResultType<String> {
    use hbb_common::{anyhow::anyhow, bail, config};
    use std::{os::windows::process::CommandExt, path::PathBuf, process::Command};

    if !config::is_outgoing_only() || !crate::platform::is_installed() {
        return Ok(serde_json::json!({"supported": false}).to_string());
    }
    let executable = PathBuf::from(crate::platform::get_install_info().3);
    let directory = executable
        .parent()
        .ok_or_else(|| anyhow!("Missing installation directory"))?;
    let shell = PathBuf::from(
        std::env::var_os("SystemRoot")
            .ok_or_else(|| anyhow!("Windows directory is unavailable"))?,
    )
    .join("System32/WindowsPowerShell/v1.0/powershell.exe");
    let output = Command::new(shell)
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(directory.join("updater/Check-ClientUpdate.ps1"))
        .creation_flags(0x08000000)
        .output()?;
    if !output.status.success() {
        bail!(
            "Update check failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    let value: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    Ok(value.to_string())
}

pub(crate) fn handle_command(args: &[String]) -> bool {
    if args.first().map(String::as_str) != Some("--crhrustdesk-update-ready") {
        return false;
    }
    let ready = if crate::platform::is_root() {
        match crate::ipc::get_config(IDLE_QUERY) {
            Ok(value) => value.as_deref() == Some("true"),
            Err(error) => {
                hbb_common::log::warn!("Cannot confirm CrhRustDesk update readiness: {error}");
                false
            }
        }
    } else {
        false
    };
    println!("{}", if ready { "READY" } else { "WAIT" });
    true
}
