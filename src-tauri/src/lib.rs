#[cfg_attr(mobile, tauri::mobile_entry_point)]
use tauri_plugin_shell::ShellExt;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            // Logs apenas em modo debug
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }

            // Iniciar sidecar Python (backend FastAPI)
            let sidecar_command = app.shell().sidecar("sentinela-api").unwrap();
            let (mut _rx, _child) = sidecar_command
                .spawn()
                .expect("Falha ao iniciar o backend sentinela-api");

            println!("Backend sidecar iniciado com sucesso!");

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
