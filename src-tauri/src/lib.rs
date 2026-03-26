#[cfg_attr(mobile, tauri::mobile_entry_point)]
use tauri_plugin_shell::ShellExt;

pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_shell::init())
    .setup(|app| {
      // 1. Configuração de Logs (apenas em Debug)
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      // 2. INICIAR SIDECAR PYTHON (SENTINELA-ENGINE)
      // O identificador "sentinela-engine" deve coincidir com o bundle.externalBin no tauri.conf.json
      let sidecar_command = app.shell().sidecar("sentinela-engine").unwrap();
      let (mut _rx, _child) = sidecar_command
        .spawn()
        .expect("Falha ao iniciar o motor do Sentinela (.bin)");
      
      println!("🚀 Motor Sidecar (.bin) iniciado pelo Tauri com sucesso!");
      
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
