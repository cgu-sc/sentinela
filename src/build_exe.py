"""
Script de Build - Gerador de Relatórios do Sentinela v3
=======================================================
Este script gera o executável usando PyInstaller.

Uso: python build_exe.py

Requisitos:
- PyInstaller: pip install pyinstaller
- Pillow: pip install pillow
"""

import subprocess
import sys
import os

def build():
    """Executa o build do executável."""
    
    print("=" * 60)
    print("BUILD - Gerador de Relatórios do Sentinela v3")
    print("=" * 60)
    
    # Verifica se PyInstaller está instalado
    try:
        import PyInstaller
        print(f"✅ PyInstaller versão: {PyInstaller.__version__}")
    except ImportError:
        print("❌ PyInstaller não encontrado. Instalando...")
        subprocess.run([sys.executable, "-m", "pip", "install", "pyinstaller"])
    
    # Verifica se Pillow está instalado
    try:
        import PIL
        print(f"✅ Pillow versão: {PIL.__version__}")
    except ImportError:
        print("❌ Pillow não encontrado. Instalando...")
        subprocess.run([sys.executable, "-m", "pip", "install", "pillow"])
    
    # Diretório atual
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Caminhos dos arquivos
    main_script = os.path.join(current_dir, "gerar_relatorio_gui.py")
    gerador_script = os.path.join(current_dir, "gerar_relatorio.py")
    icon_file = os.path.join(current_dir, "Icone.ico")
    logo_file = os.path.join(current_dir, "logo_sentinela.png")
    
    # Verifica arquivos necessários
    print("\n📁 Verificando arquivos...")
    
    if not os.path.exists(main_script):
        print(f"❌ Arquivo não encontrado: {main_script}")
        return False
    print(f"  ✅ {main_script}")
    
    if not os.path.exists(gerador_script):
        print(f"❌ Arquivo não encontrado: {gerador_script}")
        return False
    print(f"  ✅ {gerador_script}")
    
    icon_option = []
    if os.path.exists(icon_file):
        print(f"  ✅ {icon_file}")
        icon_option = [f"--icon={icon_file}"]
    else:
        print(f"  ⚠️ Ícone não encontrado: {icon_file}")
    
    logo_option = []
    if os.path.exists(logo_file):
        print(f"  ✅ {logo_file}")
        logo_option = [f"--add-data={logo_file};."]
    else:
        print(f"  ⚠️ Logo não encontrada: {logo_file}")
    
    # Comando PyInstaller otimizado para tamanho mínimo
    print("\n🔨 Iniciando build...")
    
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--onefile",                          # Arquivo único
        "--windowed",                         # Sem console
        "--name=SentinelaRelatorios",         # Nome do executável
        f"--add-data={gerador_script};.",     # Inclui o módulo gerador
        "--clean",                            # Limpa cache
        "--noconfirm",                        # Não pede confirmação
        "--hidden-import=pyodbc",
        "--hidden-import=pandas",
        "--hidden-import=xlsxwriter",  # usado pelo ExcelWriter
        "--hidden-import=secrets",
        "--hidden-import=aba_crm",

        # Exclusões para reduzir tamanho
        "--exclude-module=matplotlib",
        "--exclude-module=scipy",
        "--exclude-module=numpy.testing",
        "--exclude-module=pytest",
        "--exclude-module=setuptools",
        "--exclude-module=pip",
        "--exclude-module=wheel",
        "--exclude-module=tkinter.test",
        "--exclude-module=unittest",
        "--exclude-module=pydoc",
        "--exclude-module=doctest",

        main_script
    ]
    
    # Adiciona ícone se existir
    if icon_option:
        cmd.insert(-1, icon_option[0])
        cmd.insert(-1, f"--add-data={icon_file};.")
    
    # Adiciona logo se existir
    if logo_option:
        cmd.insert(-1, logo_option[0])
    
    print(f"\n📋 Comando: {' '.join(cmd)}\n")
    
    result = subprocess.run(cmd, cwd=current_dir)
    
    if result.returncode == 0:
        print("\n" + "=" * 60)
        print("✅ BUILD CONCLUÍDO COM SUCESSO!")
        print("=" * 60)
        
        exe_path = os.path.join(current_dir, "dist", "SentinelaRelatorios.exe")
        if os.path.exists(exe_path):
            size_mb = os.path.getsize(exe_path) / (1024 * 1024)
            print(f"\n📦 Executável gerado: {exe_path}")
            print(f"📏 Tamanho: {size_mb:.1f} MB")
        
        print("\n📝 Para distribuir, copie:")
        print(f"   - dist/SentinelaRelatorios.exe")
        print("\n⚠️  Lembre-se: O executável requer acesso ao servidor SDH-DIE-BD")
        
        return True
    else:
        print("\n❌ ERRO NO BUILD!")
        return False


if __name__ == "__main__":
    build()
