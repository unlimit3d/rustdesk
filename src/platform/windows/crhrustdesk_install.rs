pub(super) fn subkey() -> String {
    let app_name = crate::get_app_name();
    let native = format!("{}Software\\{app_name}\\InstallState\\{app_name}", super::HKLM_PREFIX);
    if !super::get_reg_of(&native, "InstallLocation").is_empty() {
        return native;
    }
    let wow = super::get_subkey(&app_name, true);
    if !super::get_reg_of(&wow, "InstallLocation").is_empty() {
        return wow;
    }
    super::get_subkey(&app_name, false)
}

pub(super) fn before_uninstall(kill_self: bool) -> super::ResultType<String> {
    let app_name = crate::get_app_name();
    let (_, _, _, exe) = super::get_install_info();
    let remove_service = super::service_control_command("remove", &exe, false)?;
    let ext = app_name.to_lowercase();
    let filter = if kill_self {
        String::new()
    } else {
        format!(" /FI \"PID ne {}\"", super::get_current_pid())
    };
    // The receiving installation owns the shared privacy broker and drivers.
    Ok(format!("
chcp 65001
{remove_service}
taskkill /F /IM {app_name}.exe{filter}
reg delete HKEY_CLASSES_ROOT\\.{ext} /f
reg delete HKEY_CLASSES_ROOT\\{ext} /f
netsh advfirewall firewall delete rule name=\"{app_name} Service\"
"))
}

pub(super) fn uninstall(kill_self: bool) -> super::ResultType<String> {
    let (subkey, path, start_menu, _) = super::get_install_info();
    let app_name = crate::get_app_name();
    let before_uninstall = before_uninstall(kill_self)?;
    Ok(format!("
{before_uninstall}
reg delete {subkey} /f
if exist \"{path}\" rd /s /q \"{path}\"
if exist \"{start_menu}\" rd /s /q \"{start_menu}\"
if exist \"%PUBLIC%\\Desktop\\{app_name}.lnk\" del /f /q \"%PUBLIC%\\Desktop\\{app_name}.lnk\"
if exist \"%PROGRAMDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\{app_name} Tray.lnk\" del /f /q \"%PROGRAMDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\{app_name} Tray.lnk\"
"))
}
