// OpenFlux Windows process host. Configuration travels through stdin, never argv.
use std::io::{self, BufRead, Write};
use csqtt_core::{ClientConfig, set_events_enabled, set_log_callback};
use tokio_util::sync::CancellationToken;

fn main() -> anyhow::Result<()> {
    if std::env::args().any(|a| a == "--version") {
        println!("OpenFlux Windows 1.0.0 | CSQTT-WIRE-3");
        return Ok(());
    }
    #[cfg(windows)] csqtt_core::tun_win::teardown();
    if std::env::args().any(|a| a == "--repair") { return Ok(()); }
    let rt = tokio::runtime::Builder::new_multi_thread().enable_all().build()?;
    let mut line = String::new();
    io::stdin().read_line(&mut line)?;
    if line.len() > 65536 { anyhow::bail!("Configuration is too large"); }
    let v: serde_json::Value = serde_json::from_str(&line)?;
    let field = |key: &str| v[key].as_str().unwrap_or_default().to_owned();
    let config = ClientConfig {
        peer: field("peer"), password: field("password"), vk: field("hashes"),
        device_id: field("device_id"), vk_js_token: field("token"),
        workers: v["workers"].as_u64().unwrap_or(18).clamp(3,54) as usize,
        vk_hash_mode: if field("hashes").is_empty() { "auto_js" } else { "manual" }.into(),
        vk_auth_mode: "vkcalls".into(), captcha_mode: "wv".into(),
        tun_uds: "wintun".into(), ..ClientConfig::default()
    };
    #[cfg(windows)] {
        let dll = std::env::current_exe()?.with_file_name("wintun.dll");
        csqtt_core::tun_win::set_dll_path_override(dll.to_string_lossy().into_owned());
    }
    set_log_callback(Box::new(|line| {
        let mut out = io::stdout().lock();
        let _ = writeln!(out, "{line}");
        let _ = out.flush();
    }));
    set_events_enabled(true);
    let cancel = CancellationToken::new();
    let stdin_cancel = cancel.clone();
    // Closing the GUI also closes the pipe and cancels the tunnel.
    std::thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if line == "STOP" { break; }
            csqtt_core::submit_control_line(line);
        }
        stdin_cancel.cancel();
    });
    let result = rt.block_on(csqtt_core::run_client(config, Some(cancel)));
    // Includes failures before the core's ordinary shutdown path.
    #[cfg(windows)] csqtt_core::tun_win::teardown();
    rt.shutdown_timeout(std::time::Duration::from_secs(3));
    if result.is_err() {
        println!("__OPENFLUX_ERROR__|Не удалось запустить подключение. Проверьте ссылку и журнал.");
        std::process::exit(1);
    }
    Ok(())
}
