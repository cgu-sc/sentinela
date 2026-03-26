#[cfg_attr(mobile, tauri::mobile_entry_point)]
use tauri_plugin_shell::ShellExt;

pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_shell::init())
    .setup(|app| {
      // Configuramos o Log (opcional, só para desenvolvimento)
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      // --- INICIAR SIDECAR PYTHON (SENTINELA-API) ---
      // 'sentinela-api' é o identificador definido no tauri.conf.json
      let sidecar_command = app.shell().sidecar("sentinela-api").unwrap();
      let (mut _rx, _child) = sidecar_command
        .spawn()
        .expect("Falha ao iniciar o backend do Sentinela (Python/FastAPI)");
      
      println!("🚀 Backend Sidecar iniciado pelo Tauri.");
      
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
