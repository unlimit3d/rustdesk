pub(crate) const IDLE_QUERY: &str = "crhrustdesk-update-ready";

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
