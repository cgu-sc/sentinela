"""
SentinelaUpdater — mini app PyWebView gráfico para auto-update.

Uso:
    SentinelaUpdater.exe --exe <caminho_do_sentinela.exe> --tmp <caminho_do_.tmp>

Executado pelo apply_update() do backend após encerrar o servidor.
Realiza as etapas de substituição e mostra progresso em janela gráfica.
"""

import argparse
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

import webview

# ---------------------------------------------------------------------------
# UI — HTML/CSS/JS inline
# ---------------------------------------------------------------------------

HTML = r"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Sentinela — Atualizando</title>
<style>
  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: #080d1a;
    color: #e2e8f0;
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    user-select: none;
  }

  body::before {
    content: '';
    position: fixed;
    inset: 0;
    background:
      radial-gradient(ellipse 90% 60% at 15% 15%, rgba(14, 165, 233, 0.13) 0%, transparent 65%),
      radial-gradient(ellipse 70% 50% at 85% 85%, rgba(99, 102, 241, 0.11) 0%, transparent 65%);
    pointer-events: none;
  }

  .card {
    position: relative;
    background: rgba(255,255,255,0.04);
    backdrop-filter: blur(24px);
    -webkit-backdrop-filter: blur(24px);
    border: 1px solid rgba(255,255,255,0.09);
    border-radius: 22px;
    padding: 36px 40px 40px;
    width: 460px;
    box-shadow: 0 32px 80px rgba(0,0,0,0.6), 0 0 0 0.5px rgba(255,255,255,0.04) inset;
  }

  /* Header */
  .header {
    display: flex;
    align-items: center;
    gap: 14px;
    margin-bottom: 32px;
  }

  .logo-icon {
    width: 42px;
    height: 42px;
    background: linear-gradient(135deg, #0ea5e9 0%, #6366f1 100%);
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 22px;
    flex-shrink: 0;
    box-shadow: 0 4px 16px rgba(14,165,233,0.35);
  }

  .header-text .title {
    font-size: 17px;
    font-weight: 600;
    color: #f1f5f9;
    letter-spacing: 0.01em;
  }

  .header-text .subtitle {
    font-size: 12.5px;
    color: #64748b;
    margin-top: 2px;
    transition: color 0.4s ease;
  }

  .header-text .subtitle.success { color: #4ade80; }

  /* Steps */
  .steps {
    display: flex;
    flex-direction: column;
    gap: 16px;
    margin-bottom: 28px;
  }

  .step {
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .step-icon {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    font-size: 13px;
    font-weight: 600;
    position: relative;
    transition: background 0.3s, border-color 0.3s;
  }

  .step-icon.pending {
    border: 2px solid rgba(255,255,255,0.10);
  }

  .step-icon.running {
    border: 2px solid transparent;
  }
  .step-icon.running::before {
    content: '';
    position: absolute;
    inset: -2px;
    border-radius: 50%;
    background: conic-gradient(from 0deg, #0ea5e9 0deg, transparent 200deg);
    animation: spin 0.9s linear infinite;
    z-index: 0;
  }
  .step-icon.running::after {
    content: '';
    position: absolute;
    inset: 2px;
    background: #0b1020;
    border-radius: 50%;
    z-index: 1;
  }
  /* inner dot while running */
  .step-icon.running .inner-dot {
    width: 7px;
    height: 7px;
    background: #0ea5e9;
    border-radius: 50%;
    position: relative;
    z-index: 2;
  }

  .step-icon.done {
    background: rgba(34, 197, 94, 0.15);
    border: 2px solid rgba(34, 197, 94, 0.6);
    color: #4ade80;
  }

  .step-icon.error {
    background: rgba(239, 68, 68, 0.14);
    border: 2px solid rgba(239, 68, 68, 0.5);
    color: #f87171;
  }

  .step-label {
    font-size: 13.5px;
    font-weight: 400;
    color: #475569;
    transition: color 0.3s ease, font-weight 0.2s ease;
    line-height: 1.4;
  }

  .step-label.running {
    color: #cbd5e1;
    font-weight: 500;
  }

  .step-label.done {
    color: #334155;
  }

  .step-label.error {
    color: #fca5a5;
    font-weight: 500;
  }

  /* Progress bar */
  .progress-track {
    height: 3px;
    background: rgba(255,255,255,0.06);
    border-radius: 3px;
    overflow: hidden;
    margin-bottom: 18px;
  }

  .progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #0ea5e9, #6366f1);
    border-radius: 3px;
    width: 0%;
    transition: width 0.55s cubic-bezier(0.4, 0, 0.2, 1);
  }

  /* Status */
  .status-text {
    font-size: 12px;
    color: #334155;
    text-align: center;
    min-height: 16px;
    margin-bottom: 4px;
    transition: color 0.3s;
  }

  /* Error message box */
  .error-box {
    display: none;
    margin-top: 14px;
    padding: 11px 14px;
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.22);
    border-radius: 10px;
    font-size: 12px;
    color: #fca5a5;
    line-height: 1.55;
  }

  /* Close button */
  .btn-close {
    display: none;
    margin-top: 18px;
    width: 100%;
    padding: 11px;
    background: linear-gradient(135deg, #0ea5e9, #6366f1);
    border: none;
    border-radius: 11px;
    color: white;
    font-size: 13.5px;
    font-weight: 500;
    cursor: pointer;
    letter-spacing: 0.01em;
    transition: opacity 0.2s, transform 0.15s;
  }
  .btn-close:hover { opacity: 0.88; transform: translateY(-1px); }
  .btn-close:active { transform: translateY(0); }
  .btn-close.error-btn { background: linear-gradient(135deg, #ef4444, #b91c1c); }

  @keyframes spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <div class="logo-icon">🛡</div>
    <div class="header-text">
      <div class="title">Sentinela</div>
      <div class="subtitle" id="subtitle">Instalando atualização...</div>
    </div>
  </div>

  <div class="steps">
    <div class="step">
      <div class="step-icon pending" id="icon-0"></div>
      <span class="step-label" id="label-0">Encerrando processos do Sentinela</span>
    </div>
    <div class="step">
      <div class="step-icon pending" id="icon-1"></div>
      <span class="step-label" id="label-1">Aguardando liberação das conexões</span>
    </div>
    <div class="step">
      <div class="step-icon pending" id="icon-2"></div>
      <span class="step-label" id="label-2">Instalando nova versão</span>
    </div>
    <div class="step">
      <div class="step-icon pending" id="icon-3"></div>
      <span class="step-label" id="label-3">Limpando arquivos temporários</span>
    </div>
    <div class="step">
      <div class="step-icon pending" id="icon-4"></div>
      <span class="step-label" id="label-4">Atualização concluída</span>
    </div>
  </div>

  <div class="progress-track">
    <div class="progress-fill" id="progress"></div>
  </div>

  <div class="status-text" id="status">Iniciando...</div>
  <div class="error-box" id="error-box"></div>
  <button class="btn-close" id="btn-close" onclick="pywebview.api.close_window()">
    Fechar
  </button>
</div>

<script>
function setStep(index, state) {
  const icon  = document.getElementById('icon-'  + index);
  const label = document.getElementById('label-' + index);

  icon.className  = 'step-icon ' + state;
  label.className = 'step-label ' + state;

  if (state === 'done') {
    icon.innerHTML = '✓';
  } else if (state === 'error') {
    icon.innerHTML = '✕';
  } else if (state === 'running') {
    icon.innerHTML = '<span class="inner-dot"></span>';
  } else {
    icon.innerHTML = '';
  }
}

function setProgress(pct) {
  document.getElementById('progress').style.width = pct + '%';
}

function setStatus(text) {
  document.getElementById('status').textContent = text;
}

function showError(msg) {
  const box = document.getElementById('error-box');
  box.textContent = msg;
  box.style.display = 'block';
  const btn = document.getElementById('btn-close');
  btn.className = 'btn-close error-btn';
  btn.style.display = 'block';
  document.getElementById('subtitle').textContent = 'Ocorreu um erro.';
}

function showClose() {
  document.getElementById('btn-close').style.display = 'block';
  const sub = document.getElementById('subtitle');
  sub.textContent = 'Concluído com sucesso!';
  sub.className = 'subtitle success';
}
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# JS bridge API
# ---------------------------------------------------------------------------

class _Api:
    """Exposto ao JS via pywebview.api."""

    def __init__(self):
        self._window = None

    def set_window(self, window) -> None:
        self._window = window

    def close_window(self) -> None:
        if self._window:
            self._window.destroy()


# ---------------------------------------------------------------------------
# Update logic (runs in background thread)
# ---------------------------------------------------------------------------

def _js(window, code: str) -> None:
    try:
        window.evaluate_js(code)
    except Exception:
        pass


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("'", "\\'").replace("\n", " ")


def _port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.15)
        return s.connect_ex(("127.0.0.1", port)) == 0


def _run_update(window, exe_path: Path, tmp_path: Path) -> None:
    current_step = 0

    def running(i: int, status: str = ""):
        nonlocal current_step
        current_step = i
        pct = i * 20
        _js(window, f"setStep({i}, 'running'); setProgress({pct});")
        if status:
            _js(window, f"setStatus('{_escape(status)}');")

    def done(i: int):
        pct = (i + 1) * 20
        _js(window, f"setStep({i}, 'done'); setProgress({pct});")

    def error(msg: str):
        _js(window, f"setStep({current_step}, 'error'); showError('{_escape(msg)}');")

    try:
        proc_name = exe_path.stem

        # ── Step 0: encerrar processos ──────────────────────────────────────
        running(0, "Encerrando processos do Sentinela...")
        subprocess.run(
            ["taskkill", "/F", "/IM", f"{proc_name}.exe"],
            capture_output=True,
        )
        time.sleep(1.5)
        done(0)

        # ── Step 1: aguardar portas ─────────────────────────────────────────
        running(1, "Aguardando portas 8002–8010 liberarem...")
        deadline = time.time() + 15
        while time.time() < deadline:
            if not any(_port_in_use(p) for p in range(8002, 8011)):
                break
            time.sleep(0.3)
        done(1)

        # ── Step 2: substituir executável ───────────────────────────────────
        running(2, "Copiando novo executável...")
        if not tmp_path.exists():
            raise RuntimeError(
                f"Arquivo de atualização não encontrado: {tmp_path.name}"
            )

        replaced = False
        deadline = time.time() + 12
        while time.time() < deadline:
            try:
                if exe_path.exists():
                    exe_path.unlink()
                shutil.copy2(str(tmp_path), str(exe_path))
                replaced = True
                break
            except OSError:
                _js(window, "setStatus('Arquivo ocupado, tentando novamente...');")
                time.sleep(0.5)

        if not replaced:
            raise RuntimeError(
                "Não foi possível substituir o executável. "
                "O arquivo pode estar em uso por outro processo."
            )
        done(2)

        # ── Step 3: limpeza ─────────────────────────────────────────────────
        running(3, "Removendo arquivos temporários...")
        tmp_path.unlink(missing_ok=True)
        # Remove o PS1 legado, se ainda existir
        ps1 = exe_path.parent / "sentinela_update.ps1"
        ps1.unlink(missing_ok=True)
        time.sleep(0.4)
        done(3)

        # ── Step 4: concluído ───────────────────────────────────────────────
        running(4, "Finalizando...")
        time.sleep(0.3)
        done(4)
        _js(window, "setProgress(100); setStatus('Atualização instalada. Você já pode abrir o Sentinela.'); showClose();")

    except Exception as exc:
        error(str(exc))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Sentinela Updater")
    parser.add_argument("--exe", required=True, help="Caminho do executável atual")
    parser.add_argument("--tmp", required=True, help="Caminho do novo executável (.tmp)")
    args = parser.parse_args()

    exe_path = Path(args.exe)
    tmp_path = Path(args.tmp)

    api = _Api()

    WIN_W, WIN_H = 480, 460

    window = webview.create_window(
        title="Sentinela — Atualizando",
        html=HTML,
        js_api=api,
        width=WIN_W,
        height=WIN_H,
        resizable=False,
        on_top=True,
        min_size=(WIN_W, WIN_H),
    )
    api.set_window(window)

    def on_shown():
        # Centraliza na tela principal
        try:
            screens = webview.screens
            if screens:
                screen = screens[0]
                if screen is not None and window is not None:
                    x = (screen.width - WIN_W) // 2
                    y = (screen.height - WIN_H) // 2
                    window.move(x, y)
        except Exception:
            pass

        # Cor da barra de título
        try:
            import ctypes
            import pywinstyles
            time.sleep(0.3)
            hwnd = ctypes.windll.user32.FindWindowW(None, "Sentinela — Atualizando")
            if hwnd:
                pywinstyles.change_header_color(hwnd, "#080d1a")
        except Exception:
            pass

        t = threading.Thread(
            target=_run_update,
            args=(window, exe_path, tmp_path),
            daemon=True,
        )
        t.start()

    webview.start(on_shown, debug=False)


if __name__ == "__main__":
    main()
