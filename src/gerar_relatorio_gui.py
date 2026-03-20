"""
SENTINELA - Gerador de Relatórios v3.3.4
====================================
Interface gráfica para geração de relatórios a partir da memória de cálculo.
Período de análise: 01/07/2015 a 10/12/2024
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageTk
import threading
import re
import os
import sys
from datetime import datetime
import ctypes
import webbrowser


def set_dark_title_bar(window):
    """
    Força a barra de título do Windows a usar o tema escuro.
    Funciona no Windows 10 (build 1809+) e Windows 11.
    """
    try:
        window.update()
        
        # Constante para ativar modo escuro na barra de título
        DWMWA_USE_IMMERSIVE_DARK_MODE = 20
        DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 = 19
        
        # Obter o handle da janela
        hwnd = ctypes.windll.user32.GetParent(window.winfo_id())
        
        # Carregar a DLL do Desktop Window Manager
        dwmapi = ctypes.windll.dwmapi
        
        # Tentar com o atributo mais recente primeiro (Windows 10 20H1+)
        rendering_policy = ctypes.c_int(1)  # 1 = True (ativar modo escuro)
        
        result = dwmapi.DwmSetWindowAttribute(
            hwnd,
            DWMWA_USE_IMMERSIVE_DARK_MODE,
            ctypes.byref(rendering_policy),
            ctypes.sizeof(rendering_policy)
        )
        
        # Se falhar, tentar com o atributo antigo (Windows 10 1809-1909)
        if result != 0:
            dwmapi.DwmSetWindowAttribute(
                hwnd,
                DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1,
                ctypes.byref(rendering_policy),
                ctypes.sizeof(rendering_policy)
            )
        
        # Forçar redesenho da janela
        window.withdraw()
        window.deiconify()
        
    except Exception:
        pass  # Ignora em sistemas não-Windows ou versões antigas

# =============================================================================
# IMPORTAÇÃO DO MÓDULO GERADOR (será importado após validação de conexão)
# =============================================================================
gerador_module = None


# =============================================================================
# CONFIGURAÇÃO DE CORES - TEMA ESCURO
# =============================================================================
COLORS = {
    'bg_dark': '#020617',       # Tailwind slate-950
    'bg_medium': '#0f172a',     # Tailwind slate-900
    'bg_light': '#1e293b',      # Tailwind slate-800
    'accent': '#3b82f6',        # Tailwind blue-500
    'accent_hover': '#2563eb',  # Tailwind blue-600
    'text_primary': '#f8fafc',  # Tailwind slate-50
    'text_secondary': '#94a3b8',# Tailwind slate-400
    'text_muted': '#64748b',    # Tailwind slate-500
    'success': '#22c55e',       # Tailwind green-500
    'warning': '#f59e0b',       # Tailwind amber-500
    'error': '#ef4444',         # Tailwind red-500
    'info': '#0ea5e9',          # Tailwind sky-500
    'border': '#1e293b',        # Tailwind slate-800
    'input_bg': '#0f172a',      # Tailwind slate-900
    'button_bg': '#2563eb',     # Tailwind blue-600
    'button_hover': '#1d4ed8',  # Tailwind blue-700
}


# =============================================================================
# CLASSE PRINCIPAL DA APLICAÇÃO
# =============================================================================
class SentinelaApp:
    def __init__(self, root):
        self.root = root
        
        # Versão Local do Sistema
        self.versao_local = "3.3.4"
        
        self.root.title(f"Gerador de Relatórios do Sentinela v{self.versao_local}")
        self.root.geometry("900x750")
        self.root.minsize(800, 650)
        self.root.configure(bg=COLORS['bg_dark'])
        
        # Variáveis
        self.tipo_completo = tk.BooleanVar(value=True)
        self.tipo_resumido = tk.BooleanVar(value=True)
        self.diretorio_saida = tk.StringVar(value=os.getcwd())
        self.processando = False
        self.cancelar = False
        self.logo_image = None  # Para manter referência da imagem
        
        # Configurar ícone se existir
        self._configurar_icone()
        
        # Forçar barra de título escura no Windows
        set_dark_title_bar(self.root)
        
        # Construir interface
        self._criar_interface()
        
        # Centralizar janela
        self._centralizar_janela()
        
        # Verificar se existe atualização obrigatória no banco
        self.root.after(100, self._verificar_versao)
    
    def _verificar_versao(self):
        """
        Consulta o banco de dados para verificar se a versão atual do executável
        é permitida. Caso contrário, obriga a atualização.
        """
        try:
            import pyodbc
            conn_str = (
                'Driver={ODBC Driver 17 for SQL Server};'
                'Server=SDH-DIE-BD;'
                'Database=temp_CGUSC;'
                'Trusted_Connection=yes;'
                'Connection Timeout=5;'
            )
            cnxn = pyodbc.connect(conn_str)
            cursor = cnxn.cursor()
            
            # Busca a versão mínima obrigatória
            cursor.execute("SELECT valor FROM fp.config_sistema WHERE chave = 'versao_minima_obrigatoria'")
            row = cursor.fetchone()
            
            if row:
                versao_minima = row[0]
                
                # Comparação simples de versão (major.minor.patch)
                def parse_version(v):
                    return [int(x) for x in re.sub(r'[^0-9.]', '', v).split('.')]
                
                v_local = parse_version(self.versao_local)
                v_minima = parse_version(versao_minima)
                
                if v_local < v_minima:
                    self._exibir_aviso_atualizacao(versao_minima)
                    return
            
            cursor.close()
            cnxn.close()
            
        except Exception as e:
            # Se não conseguir conectar ao banco para validar a versão, 
            # apenas loga mas permite abrir (ou bloqueia se preferir ser mais rígido)
            print(f"Aviso: Não foi possível validar a versão do sistema: {e}")

    def _exibir_aviso_atualizacao(self, versao_minima):
        """Exibe uma janela personalizada de atualização obrigatória."""
        aviso = tk.Toplevel(self.root) 
        aviso.title("Atualização Obrigatória")
        aviso.geometry("500x380")
        aviso.resizable(False, False)
        aviso.configure(bg=COLORS['bg_dark'])
        # Não usar transient enquanto root está oculto pode ser melhor em alguns casos,
        # mas vamos garantir o lift e focus.
        aviso.lift()
        aviso.focus_force()
        aviso.grab_set()
        
        # Centralizar na tela
        aviso.update_idletasks()
        x = (aviso.winfo_screenwidth() // 2) - (250)
        y = (aviso.winfo_screenheight() // 2) - (160)
        aviso.geometry(f"+{x}+{y}")
        
        # Forçar modo escuro na barra de título do aviso
        set_dark_title_bar(aviso)
        
        # Container
        content = tk.Frame(aviso, bg=COLORS['bg_dark'], padx=30, pady=20)
        content.pack(fill=tk.BOTH, expand=True)
        
        # Ícone de Alerta Grande
        lbl_icon = tk.Label(
            content, 
            text="⚠️", 
            font=("Segoe UI", 48), 
            fg=COLORS['error'], 
            bg=COLORS['bg_dark']
        )
        lbl_icon.pack(pady=(0, 10))
        
        # Título
        lbl_titulo = tk.Label(
            content,
            text="Versão Desatualizada",
            font=("Segoe UI", 16, "bold"),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark']
        )
        lbl_titulo.pack()
        
        # Mensagem
        msg = (
            f"Sua versão atual ({self.versao_local}) não é mais suportada.\n"
            f"A versão mínima exigida agora é a {versao_minima}.\n\n"
            "Para continuar utilizando o Sentinela, por favor\n"
            "instale a versão mais recente disponível na Rede."
        )
        
        lbl_msg = tk.Label(
            content,
            text=msg,
            font=("Segoe UI", 10),
            fg=COLORS['text_secondary'],
            bg=COLORS['bg_dark'],
            justify=tk.CENTER,
            pady=15
        )
        lbl_msg.pack()

        # Frame para os botões
        btns_frame = tk.Frame(content, bg=COLORS['bg_dark'])
        btns_frame.pack(pady=(10, 0))
        
        # Botão Baixar Nova Versão
        url = "https://cgugovbr.sharepoint.com/sites/intracgu-sc/Documentos%20Compartilhados/Forms/AllItems.aspx?id=%2Fsites%2Fintracgu%2Dsc%2FDocumentos%20Compartilhados%2FSentinela%2FGerador%20de%20Relat%C3%B3rios&viewid=15b467ac%2Ddda9%2D4238%2Db989%2Dcd22a2d9d002&p=true&ct=1772215261067&or=Teams%2DHL&LOF=1"
        btn_baixar = tk.Button(
            btns_frame,
            text="📥 Baixar Nova Versão",
            font=("Segoe UI", 10, "bold"),
            bg=COLORS['accent'],
            fg=COLORS['text_primary'],
            activebackground=COLORS['accent_hover'],
            activeforeground=COLORS['text_primary'],
            relief=tk.FLAT,
            padx=20,
            pady=8,
            cursor="hand2",
            command=lambda: webbrowser.open(url)
        )
        btn_baixar.pack(side=tk.LEFT, padx=5)
        
        # Botão Sair
        btn_sair = tk.Button(
            btns_frame,
            text="Sair",
            font=("Segoe UI", 10, "bold"),
            bg=COLORS['button_bg'],
            fg=COLORS['text_primary'],
            activebackground=COLORS['button_hover'],
            activeforeground=COLORS['text_primary'],
            relief=tk.FLAT,
            padx=20,
            pady=8,
            cursor="hand2",
            command=lambda: [self.root.destroy(), sys.exit(0)]
        )
        btn_sair.pack(side=tk.LEFT, padx=5)
        
        # Bloquear o encerramento da janela pelo 'X' sem sair do app
        aviso.protocol("WM_DELETE_WINDOW", lambda: [self.root.destroy(), sys.exit(0)])

    def _exibir_erro_conexao(self):
        """Exibe uma janela personalizada de erro de conexão com o banco."""
        erro_win = tk.Toplevel(self.root) 
        erro_win.title("Erro de Conexão")
        erro_win.geometry("500x350")
        erro_win.resizable(False, False)
        erro_win.configure(bg=COLORS['bg_dark'])
        erro_win.lift()
        erro_win.focus_force()
        erro_win.grab_set()
        
        # Centralizar na tela
        erro_win.update_idletasks()
        x = (erro_win.winfo_screenwidth() // 2) - (250)
        y = (erro_win.winfo_screenheight() // 2) - (175)
        erro_win.geometry(f"+{x}+{y}")
        
        # Forçar modo escuro na barra de título
        set_dark_title_bar(erro_win)
        
        # Container
        content = tk.Frame(erro_win, bg=COLORS['bg_dark'], padx=30, pady=20)
        content.pack(fill=tk.BOTH, expand=True)
        
        # Ícone de Erro
        lbl_icon = tk.Label(
            content, 
            text="❌", 
            font=("Segoe UI", 48), 
            fg=COLORS['error'], 
            bg=COLORS['bg_dark']
        )
        lbl_icon.pack(pady=(0, 10))
        
        # Título
        lbl_titulo = tk.Label(
            content,
            text="Falha na Conexão",
            font=("Segoe UI", 16, "bold"),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark']
        )
        lbl_titulo.pack()
        
        # Mensagem
        msg = (
            "Não foi possível conectar com o CGUData.\n\n"
            "Por favor, verifique sua conexão com a Rede (VPN)\n"
            "ou solicite acesso ao servidor SDH-DIE-BD."
        )
        
        lbl_msg = tk.Label(
            content,
            text=msg,
            font=("Segoe UI", 10),
            fg=COLORS['text_secondary'],
            bg=COLORS['bg_dark'],
            justify=tk.CENTER,
            pady=15
        )
        lbl_msg.pack()

        # Botão OK
        btn_ok = tk.Button(
            content,
            text="Entendido",
            font=("Segoe UI", 10, "bold"),
            bg=COLORS['button_bg'],
            fg=COLORS['text_primary'],
            activebackground=COLORS['button_hover'],
            activeforeground=COLORS['text_primary'],
            relief=tk.FLAT,
            padx=30,
            pady=8,
            cursor="hand2",
            command=erro_win.destroy
        )
        btn_ok.pack(pady=(10, 0))

    
    def _configurar_icone(self):
        """Configura o ícone da aplicação."""
        try:
            if getattr(sys, 'frozen', False):
                base_path = sys._MEIPASS
            else:
                base_path = os.path.dirname(os.path.abspath(__file__))
            
            # Primeiro define o .ico para a janela
            icon_path = os.path.join(base_path, 'Icone.ico')
            if os.path.exists(icon_path):
                self.root.iconbitmap(icon_path)
            
            # Depois usa PNG para a barra de tarefas
            icon_png_path = os.path.join(base_path, 'Icone2.ico')
            if os.path.exists(icon_png_path):
                img = Image.open(icon_png_path)
                img_copy = img.copy()  # Cria uma cópia independente
                self._taskbar_icon = ImageTk.PhotoImage(img_copy)
                self.root.iconphoto(True, self._taskbar_icon)
                img.close()
                
        except Exception:
            pass
    
    def _carregar_logo(self, tamanho=48):
        """Carrega e redimensiona a logo do Sentinela."""
        try:
            if getattr(sys, 'frozen', False):
                base_path = sys._MEIPASS
            else:
                base_path = os.path.dirname(os.path.abspath(__file__))
            
            logo_path = os.path.join(base_path, 'logo_sentinela.png')
            if os.path.exists(logo_path):
                img = Image.open(logo_path)
                img = img.resize((tamanho, tamanho), Image.LANCZOS)
                return ImageTk.PhotoImage(img)
        except Exception:
            pass
        return None
    
    def _centralizar_janela(self):
        """Centraliza a janela na tela."""
        self.root.update_idletasks()
        width = self.root.winfo_width()
        height = self.root.winfo_height()
        x = (self.root.winfo_screenwidth() // 2) - (width // 2)
        y = (self.root.winfo_screenheight() // 2) - (height // 2)
        self.root.geometry(f'{width}x{height}+{x}+{y}')
    
    def _criar_interface(self):
        """Cria todos os componentes da interface."""
        # Container principal com padding
        main_container = tk.Frame(self.root, bg=COLORS['bg_dark'])
        main_container.pack(fill=tk.BOTH, expand=True, padx=20, pady=15)
        
        # === CABEÇALHO ===
        self._criar_cabecalho(main_container)
        
        # === ÁREA DE ENTRADA DE CNPJs ===
        self._criar_area_cnpjs(main_container)
        
        # === OPÇÕES ===
        self._criar_opcoes(main_container)
        
        # === BOTÕES DE AÇÃO ===
        self._criar_botoes(main_container)
        
        # === ÁREA DE LOG ===
        self._criar_area_log(main_container)
        
        # === BARRA DE PROGRESSO ===
        self._criar_barra_progresso(main_container)
    
    def _criar_cabecalho(self, parent):
        """Cria o cabeçalho com título e subtítulo."""
        header_frame = tk.Frame(parent, bg=COLORS['bg_dark'])
        header_frame.pack(fill=tk.X, pady=(0, 20))
        
        # Frame para logo + título
        title_frame = tk.Frame(header_frame, bg=COLORS['bg_dark'])
        title_frame.pack(anchor="w")
        
        # Logo
        self.logo_image = self._carregar_logo(80)
        if self.logo_image:
            logo_label = tk.Label(
                title_frame,
                image=self.logo_image,
                bg=COLORS['bg_dark']
            )
            logo_label.pack(side=tk.LEFT, padx=(0, 12))
        
        # Container para textos
        text_frame = tk.Frame(title_frame, bg=COLORS['bg_dark'])
        text_frame.pack(side=tk.LEFT)
        
        # Título principal
        titulo = tk.Label(
            text_frame,
            text=f"Gerador de Relatórios do Sentinela v{self.versao_local}",
            font=("Segoe UI", 22, "bold"),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark']
        )
        titulo.pack(anchor="w")
        
        # Subtítulo
        subtitulo = tk.Label(
            text_frame,
            text="Período de 01/07/2015 a 10/12/2024",
            font=("Segoe UI", 11),
            fg=COLORS['text_secondary'],
            bg=COLORS['bg_dark']
        )
        subtitulo.pack(anchor="w", pady=(2, 0))
        
        # Linha separadora
        separator = tk.Frame(header_frame, bg=COLORS['accent'], height=3)
        separator.pack(fill=tk.X, pady=(15, 0))
    
    def _criar_area_cnpjs(self, parent):
        """Cria a área de entrada de CNPJs."""
        frame = tk.Frame(parent, bg=COLORS['bg_dark'])
        frame.pack(fill=tk.X, pady=(0, 15))
        
        # Label
        label = tk.Label(
            frame,
            text="📋 CNPJs (separados por vírgula, ponto-e-vírgula ou Enter):",
            font=("Segoe UI", 10, "bold"),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark']
        )
        label.pack(anchor="w", pady=(0, 5))
        
        # Frame para o Text widget com borda
        text_frame = tk.Frame(frame, bg=COLORS['border'], padx=2, pady=2)
        text_frame.pack(fill=tk.X)
        
        # Text widget para CNPJs
        self.txt_cnpjs = tk.Text(
            text_frame,
            height=5,
            font=("Consolas", 11),
            bg=COLORS['input_bg'],
            fg=COLORS['text_primary'],
            insertbackground=COLORS['text_primary'],
            selectbackground=COLORS['accent'],
            relief=tk.FLAT,
            wrap=tk.WORD,
            padx=10,
            pady=8
        )
        self.txt_cnpjs.pack(fill=tk.X, side=tk.LEFT, expand=True)
        
        # Scrollbar
        scrollbar = tk.Scrollbar(text_frame, command=self.txt_cnpjs.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.txt_cnpjs.config(yscrollcommand=scrollbar.set)
        
        # Placeholder
        self._adicionar_placeholder()
    
    def _adicionar_placeholder(self):
        """Adiciona texto de placeholder no campo de CNPJs."""
        placeholder = "Digite os CNPJs aqui...\nExemplo: 12.345.678/0001-90, 98765432000199"
        self.txt_cnpjs.insert("1.0", placeholder)
        self.txt_cnpjs.config(fg=COLORS['text_muted'])
        
        def on_focus_in(event):
            if self.txt_cnpjs.get("1.0", "end-1c") == placeholder:
                self.txt_cnpjs.delete("1.0", tk.END)
                self.txt_cnpjs.config(fg=COLORS['text_primary'])
        
        def on_focus_out(event):
            if not self.txt_cnpjs.get("1.0", "end-1c").strip():
                self.txt_cnpjs.insert("1.0", placeholder)
                self.txt_cnpjs.config(fg=COLORS['text_muted'])
        
        self.txt_cnpjs.bind("<FocusIn>", on_focus_in)
        self.txt_cnpjs.bind("<FocusOut>", on_focus_out)
    
    def _criar_opcoes(self, parent):
        """Cria as opções de tipo de relatório e diretório de saída."""
        frame = tk.Frame(parent, bg=COLORS['bg_dark'])
        frame.pack(fill=tk.X, pady=(0, 15))
        
        # === Tipo de Relatório (Checkboxes) ===
        tipo_frame = tk.Frame(frame, bg=COLORS['bg_dark'])
        tipo_frame.pack(fill=tk.X, pady=(0, 10))
        
        label_tipo = tk.Label(
            tipo_frame,
            text="📊 Tipo de Relatório:",
            font=("Segoe UI", 10, "bold"),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark']
        )
        label_tipo.pack(side=tk.LEFT, padx=(0, 15))
        
        # Checkbox Completo
        cb_completo = tk.Checkbutton(
            tipo_frame,
            text="Completo",
            variable=self.tipo_completo,
            font=("Segoe UI", 10),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark'],
            selectcolor=COLORS['bg_medium'],
            activebackground=COLORS['bg_dark'],
            activeforeground=COLORS['accent_hover']
        )
        cb_completo.pack(side=tk.LEFT, padx=(0, 20))
        
        # Checkbox Resumido
        cb_resumido = tk.Checkbutton(
            tipo_frame,
            text="Resumido",
            variable=self.tipo_resumido,
            font=("Segoe UI", 10),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark'],
            selectcolor=COLORS['bg_medium'],
            activebackground=COLORS['bg_dark'],
            activeforeground=COLORS['accent_hover']
        )
        cb_resumido.pack(side=tk.LEFT, padx=(0, 20))
        
        # === Diretório de Saída ===
        dir_frame = tk.Frame(frame, bg=COLORS['bg_dark'])
        dir_frame.pack(fill=tk.X)
        
        label_dir = tk.Label(
            dir_frame,
            text="📁 Diretório de Saída:",
            font=("Segoe UI", 10, "bold"),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark']
        )
        label_dir.pack(anchor="w", pady=(0, 5))
        
        # Frame container com borda fina
        dir_container = tk.Frame(dir_frame, bg=COLORS['border'], padx=1, pady=1)
        dir_container.pack(fill=tk.X)
        
        # Frame interno
        dir_input_frame = tk.Frame(dir_container, bg=COLORS['input_bg'])
        dir_input_frame.pack(fill=tk.X)
        
        self.entry_dir = tk.Entry(
            dir_input_frame,
            textvariable=self.diretorio_saida,
            font=("Consolas", 10),
            bg=COLORS['input_bg'],
            fg=COLORS['text_primary'],
            insertbackground=COLORS['text_primary'],
            relief=tk.FLAT,
            borderwidth=0
        )
        self.entry_dir.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=10, pady=8)
        
        btn_browse = tk.Button(
            dir_input_frame,
            text="📂 Procurar",
            font=("Segoe UI", 9),
            bg=COLORS['input_bg'],
            fg=COLORS['text_primary'],
            activebackground=COLORS['input_bg'],
            activeforeground=COLORS['input_bg'],
            relief=tk.FLAT,
            cursor="hand2",
            padx=12,
            pady=4,
            command=self._selecionar_diretorio
        )
        btn_browse.pack(side=tk.RIGHT, padx=6, pady=6)
        
        # Efeito hover no botão procurar
        btn_browse.bind("<Enter>", lambda e: btn_browse.config(bg=COLORS['accent']))
        btn_browse.bind("<Leave>", lambda e: btn_browse.config(bg=COLORS['input_bg']))
    
    def _criar_botoes(self, parent):
        """Cria os botões de ação."""
        frame = tk.Frame(parent, bg=COLORS['bg_dark'])
        frame.pack(fill=tk.X, pady=(0, 15))
        
        # Botão Gerar Relatórios
        self.btn_gerar = tk.Button(
            frame,
            text="🚀 Gerar Relatórios",
            font=("Segoe UI", 11, "bold"),
            bg=COLORS['button_bg'],
            fg=COLORS['text_primary'],
            activebackground=COLORS['button_hover'],
            activeforeground=COLORS['text_primary'],
            relief=tk.FLAT,
            cursor="hand2",
            padx=25,
            pady=10,
            command=self._iniciar_processamento
        )
        self.btn_gerar.pack(side=tk.LEFT, padx=(0, 10))
        
        # Efeito hover
        self.btn_gerar.bind("<Enter>", lambda e: self.btn_gerar.config(bg=COLORS['button_hover']))
        self.btn_gerar.bind("<Leave>", lambda e: self.btn_gerar.config(bg=COLORS['button_bg']))
        
        # Botão Cancelar (inicialmente oculto)
        self.btn_cancelar = tk.Button(
            frame,
            text="⏹️ Cancelar",
            font=("Segoe UI", 11, "bold"),
            bg=COLORS['error'],
            fg=COLORS['text_primary'],
            activebackground="#ff6b6b",
            activeforeground=COLORS['text_primary'],
            relief=tk.FLAT,
            cursor="hand2",
            padx=25,
            pady=10,
            command=self._cancelar_processamento
        )
        
        # Botão Limpar
        btn_limpar = tk.Button(
            frame,
            text="🗑️ Limpar",
            font=("Segoe UI", 10),
            bg=COLORS['accent'],
            fg=COLORS['text_primary'],
            activebackground=COLORS['accent_hover'],
            activeforeground=COLORS['text_primary'],
            relief=tk.FLAT,
            cursor="hand2",
            padx=20,
            pady=10,
            command=self._limpar_campos
        )
        btn_limpar.pack(side=tk.RIGHT)
        
        # Efeito hover no botão limpar
        btn_limpar.bind("<Enter>", lambda e: btn_limpar.config(bg=COLORS['accent_hover']))
        btn_limpar.bind("<Leave>", lambda e: btn_limpar.config(bg=COLORS['accent']))
    
    def _criar_area_log(self, parent):
        """Cria a área de log de execução."""
        frame = tk.Frame(parent, bg=COLORS['bg_dark'])
        frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))
        
        # Label
        label = tk.Label(
            frame,
            text="📋 Log de Execução:",
            font=("Segoe UI", 10, "bold"),
            fg=COLORS['text_primary'],
            bg=COLORS['bg_dark']
        )
        label.pack(anchor="w", pady=(0, 5))
        
        # Frame para o Text widget com borda
        log_frame = tk.Frame(frame, bg=COLORS['border'], padx=2, pady=2)
        log_frame.pack(fill=tk.BOTH, expand=True)
        
        # Text widget para log
        self.txt_log = tk.Text(
            log_frame,
            font=("Consolas", 10),
            bg=COLORS['input_bg'],
            fg=COLORS['text_primary'],
            insertbackground=COLORS['text_primary'],
            relief=tk.FLAT,
            wrap=tk.WORD,
            padx=10,
            pady=8,
            state=tk.DISABLED
        )
        self.txt_log.pack(fill=tk.BOTH, expand=True, side=tk.LEFT)
        
        # Scrollbar
        scrollbar = tk.Scrollbar(log_frame, command=self.txt_log.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.txt_log.config(yscrollcommand=scrollbar.set)
        
        # Configurar tags para cores no log
        self.txt_log.tag_configure("info", foreground=COLORS['info'])
        self.txt_log.tag_configure("success", foreground=COLORS['success'])
        self.txt_log.tag_configure("warning", foreground=COLORS['warning'])
        self.txt_log.tag_configure("error", foreground=COLORS['error'])
        self.txt_log.tag_configure("header", foreground=COLORS['accent'], font=("Consolas", 10, "bold"))
        self.txt_log.tag_configure("timestamp", foreground=COLORS['text_muted'])
        self.txt_log.tag_configure("cnpj", foreground="#00d4ff", font=("Consolas", 10, "bold"))
    
    def _criar_barra_progresso(self, parent):
        """Cria a barra de progresso."""
        frame = tk.Frame(parent, bg=COLORS['bg_dark'])
        frame.pack(fill=tk.X)
        
        # Label de progresso
        self.lbl_progresso = tk.Label(
            frame,
            text="Aguardando...",
            font=("Segoe UI", 9),
            fg=COLORS['text_secondary'],
            bg=COLORS['bg_dark']
        )
        self.lbl_progresso.pack(anchor="w", pady=(0, 3))
        
        # Estilo da barra de progresso
        style = ttk.Style()
        style.theme_use('default')
        style.configure(
            "Custom.Horizontal.TProgressbar",
            troughcolor=COLORS['bg_medium'],
            background=COLORS['accent'],
            darkcolor=COLORS['accent'],
            lightcolor=COLORS['accent'],
            bordercolor=COLORS['border'],
            thickness=20
        )
        
        # Barra de progresso
        self.progressbar = ttk.Progressbar(
            frame,
            style="Custom.Horizontal.TProgressbar",
            orient=tk.HORIZONTAL,
            mode='determinate'
        )
        self.progressbar.pack(fill=tk.X)
    
    # =========================================================================
    # MÉTODOS DE AÇÃO
    # =========================================================================
    
    def _selecionar_diretorio(self):
        """Abre diálogo para seleção de diretório."""
        diretorio = filedialog.askdirectory(
            title="Selecione o diretório de saída",
            initialdir=self.diretorio_saida.get()
        )
        if diretorio:
            self.diretorio_saida.set(diretorio)
    
    def _limpar_campos(self):
        """Limpa todos os campos."""
        # Limpar CNPJs
        self.txt_cnpjs.delete("1.0", tk.END)
        self._adicionar_placeholder()
        
        # Limpar log
        self.txt_log.config(state=tk.NORMAL)
        self.txt_log.delete("1.0", tk.END)
        self.txt_log.config(state=tk.DISABLED)
        
        # Resetar progresso
        self.progressbar['value'] = 0
        self.lbl_progresso.config(text="Aguardando...")
    
    def _log(self, mensagem, tipo="info"):
        """Adiciona mensagem ao log com formatação."""
        self.txt_log.config(state=tk.NORMAL)
        
        # Timestamp
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.txt_log.insert(tk.END, f"[{timestamp}] ", "timestamp")
        
        # Ícone baseado no tipo
        icones = {
            "info": "ℹ️ ",
            "success": "✅ ",
            "warning": "⚠️ ",
            "error": "❌ ",
            "header": "═══ ",
            "cnpj": "📄 "
        }

        icone = icones.get(tipo, "")

        # Mensagem
        self.txt_log.insert(tk.END, f"{icone}{mensagem}\n", tipo)

        self.txt_log.config(state=tk.DISABLED)
        self.txt_log.see(tk.END)
        self.root.update_idletasks()

    def _log_separador(self, texto=""):
        """Adiciona linha separadora no log."""
        self.txt_log.config(state=tk.NORMAL)
        if texto:
            linha = f"{'═' * 20} {texto} {'═' * 20}"
        else:
            linha = "═" * 60
        self.txt_log.insert(tk.END, f"{linha}\n", "header")
        self.txt_log.config(state=tk.DISABLED)
        self.txt_log.see(tk.END)

    def _extrair_cnpjs(self, texto):
        """Extrai e limpa CNPJs do texto de entrada."""
        # Remove placeholder se existir
        placeholder = "Digite os CNPJs aqui...\nExemplo: 12.345.678/0001-90, 98765432000199"
        if texto.strip() == placeholder:
            return []

        # Substitui separadores por espaço
        texto_limpo = texto.replace(',', ' ').replace(';', ' ').replace('\n', ' ')

        # Divide por espaços e filtra vazios
        partes = [p.strip() for p in texto_limpo.split() if p.strip()]

        cnpjs = []
        for parte in partes:
            # Remove caracteres não numéricos
            cnpj_limpo = re.sub(r'[^\d]', '', parte)
            if cnpj_limpo:
                cnpjs.append(cnpj_limpo)

        return cnpjs

    def _validar_cnpj(self, cnpj):
        """Valida se o CNPJ tem 14 dígitos."""
        return len(cnpj) == 14 and cnpj.isdigit()

    def _formatar_cnpj(self, cnpj):
        """Formata CNPJ para exibição."""
        if len(cnpj) == 14:
            return f"{cnpj[:2]}.{cnpj[2:5]}.{cnpj[5:8]}/{cnpj[8:12]}-{cnpj[12:]}"
        return cnpj

    def _atualizar_progresso(self, atual, total):
        """Atualiza a barra de progresso."""
        percentual = (atual / total) * 100 if total > 0 else 0
        self.progressbar['value'] = percentual
        self.lbl_progresso.config(text=f"Processando: {atual}/{total} CNPJs ({percentual:.0f}%)")
        self.root.update_idletasks()

    def _iniciar_processamento(self):
        """Inicia o processamento em thread separada."""
        if self.processando:
            return

        # Verificar se pelo menos um tipo de relatório está selecionado
        if not self.tipo_completo.get() and not self.tipo_resumido.get():
            messagebox.showwarning(
                "Atenção",
                "Por favor, selecione pelo menos um tipo de relatório (Completo ou Resumido)."
            )
            return

        # Extrair CNPJs
        texto_cnpjs = self.txt_cnpjs.get("1.0", tk.END)
        cnpjs = self._extrair_cnpjs(texto_cnpjs)

        if not cnpjs:
            messagebox.showwarning(
                "Atenção",
                "Por favor, insira pelo menos um CNPJ para processar."
            )
            return

        # Limpar log anterior
        self.txt_log.config(state=tk.NORMAL)
        self.txt_log.delete("1.0", tk.END)
        self.txt_log.config(state=tk.DISABLED)

        # Iniciar thread de processamento
        self.processando = True
        self.cancelar = False

        # Alternar botões
        self.btn_gerar.pack_forget()
        self.btn_cancelar.pack(side=tk.LEFT, padx=(0, 10))

        thread = threading.Thread(target=self._processar_cnpjs, args=(cnpjs,), daemon=True)
        thread.start()

    def _cancelar_processamento(self):
        """Sinaliza cancelamento do processamento."""
        self.cancelar = True
        self._log("Cancelamento solicitado... Aguarde a finalização do CNPJ atual.", "warning")



    def _processar_cnpjs(self, cnpjs):
        """Processa a lista de CNPJs (executado em thread separada)."""
        global gerador_module
        import importlib.util
        import traceback

        # Montar string de tipos selecionados para log
        tipos_str = []
        if self.tipo_completo.get():
            tipos_str.append("COMPLETO")
        if self.tipo_resumido.get():
            tipos_str.append("RESUMIDO")

        self._log_separador("INÍCIO DO PROCESSAMENTO")
        self._log(f"Total de CNPJs informados: {len(cnpjs)}", "info")
        self._log(f"Tipo(s) de relatório: {', '.join(tipos_str)}", "info")
        self._log(f"Diretório de saída: {self.diretorio_saida.get()}", "info")
        self._log_separador()

        # 1. Validar CNPJs
        cnpjs_validos = []
        cnpjs_invalidos = []

        self._log("Validando CNPJs...", "info")

        for cnpj in cnpjs:
            if self._validar_cnpj(cnpj):
                cnpjs_validos.append(cnpj)
                self._log(f"CNPJ {self._formatar_cnpj(cnpj)} - Válido", "success")
            else:
                cnpjs_invalidos.append(cnpj)
                self._log(f"CNPJ {cnpj} - Inválido (deve ter 14 dígitos numéricos)", "error")

        if cnpjs_invalidos:
            self._log(f"\n{len(cnpjs_invalidos)} CNPJ(s) inválido(s) serão ignorados.", "warning")

        if not cnpjs_validos:
            self._log("\nNenhum CNPJ válido para processar.", "error")
            self._finalizar_processamento(False)
            return

        self._log(f"\n{len(cnpjs_validos)} CNPJ(s) válido(s) serão processados.", "info")
        self._log_separador("CONECTANDO AO BANCO DE DADOS")

        # 2. Carregar Módulo Gerador Dinamicamente
        try:
            # Encontrar o caminho do módulo (compatível com PyInstaller e Dev)
            if getattr(sys, 'frozen', False):
                base_path = sys._MEIPASS
            else:
                base_path = os.path.dirname(os.path.abspath(__file__))

            module_path = os.path.join(base_path, 'gerar_relatorio.py')

            if not os.path.exists(module_path):
                # Tenta no diretório atual como fallback
                module_path = 'gerar_relatorio.py'

            spec = importlib.util.spec_from_file_location("gerador", module_path)
            gerador_module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(gerador_module)

            self._log("Módulo gerador carregado com sucesso.", "success")

        except Exception as e:
            self._log(f"Erro crítico ao carregar módulo gerador: {e}", "error")
            self._finalizar_processamento(False)
            return

        # 3. Conectar ao Banco de Dados
        try:
            self._log("Conectando ao servidor SQL (SDH-DIE-BD)...", "info")
            conn, cursor = gerador_module.conectar_bd()
            self._log("Conexão estabelecida com sucesso!", "success")

        except Exception as e:
            self._log(f"ERRO: Falha ao conectar ao banco de dados.", "error")
            self._log(f"Detalhes: {str(e)}", "error")
            self._log("\nVerifique se você tem acesso ao servidor SDH-DIE-BD e se a VPN está ativa.", "warning")
            
            # Exibir janela de erro na thread principal
            self.root.after(0, self._exibir_erro_conexao)
            
            self._finalizar_processamento(False)
            return

        # 4. Carregar Dados Auxiliares (Farmácias e Medicamentos)
        self._log("\nCarregando dados auxiliares...", "info")
        try:
            dados_farmacias, dados_medicamentos = gerador_module.carregar_dados_auxiliares(cursor)
            self._log(f"Dados de farmácias carregados: {len(dados_farmacias)} registros", "success")
            self._log(f"Dados de medicamentos carregados: {len(dados_medicamentos)} registros", "success")
        except Exception as e:
            self._log(f"Erro ao carregar dados auxiliares: {e}", "error")
            cursor.close()
            conn.close()
            self._finalizar_processamento(False)
            return

        # 5. Processar cada CNPJ (Loop Principal)
        self._log_separador("GERANDO RELATÓRIOS")

        total = len(cnpjs_validos)
        sucesso = 0
        erros = 0
        diretorio = self.diretorio_saida.get()

        # Determinar tipos de relatório a gerar baseado nos checkboxes
        tipos = []
        if self.tipo_completo.get():
            tipos.append(1)
        if self.tipo_resumido.get():
            tipos.append(2)

        for i, cnpj in enumerate(cnpjs_validos, 1):
            if self.cancelar:
                self._log("\nProcessamento cancelado pelo usuário.", "warning")
                break

            self._atualizar_progresso(i - 1, total)
            cnpj_fmt = self._formatar_cnpj(cnpj)

            self._log(f"\n[{i}/{total}] Processando CNPJ: {cnpj_fmt}", "cnpj")

            try:
                # 5.1 Carregar Memória de Cálculo e ID do Processamento
                self._log("  └─ Carregando memória de cálculo...", "info")
                # IMPORTANTE: Captura o id_proc retornado
                dados_memoria, id_proc = gerador_module.carregar_memoria_calculo(cursor, cnpj)

                if not dados_memoria:
                    self._log(f"  └─ Nenhum dado encontrado para este CNPJ", "warning")
                    erros += 1
                    continue

                self._log(f"  └─ Encontrados {len(dados_memoria)} registros (ID Processamento: {id_proc})", "success")

                # 5.2 Buscar Indicadores de Risco
                self._log("  └─ Buscando indicadores de risco...", "info")
                dados_risco = gerador_module.buscar_dados_risco(cursor, cnpj)

                if dados_risco:
                    score = dados_risco.get('SCORE_RISCO_FINAL', 'N/A')
                    self._log(f"  └─ Score de risco: {score}", "success")
                else:
                    self._log("  └─ Dados de risco não encontrados", "warning")

                # 5.3 Buscar Dados de Prescritores (CRÍTICO PARA ABA CRM)
                self._log("  └─ Buscando dados de prescritores...", "info")
                dados_prescritores = gerador_module.buscar_dados_prescritores(cursor, cnpj)
                top20_prescritores = gerador_module.buscar_top20_prescritores(cursor, cnpj)

                if dados_prescritores:
                    score_presc = dados_prescritores.get('score_prescritores', 'N/A')
                    self._log(f"  └─ Dados de prescritores encontrados (Score: {score_presc})", "success")
                else:
                    self._log(f"  └─ Sem dados de prescritores para este CNPJ.", "warning")

                # 5.4 Buscar Dados de Falecidos (NOVO)
                self._log("  └─ Buscando vendas para falecidos...", "info")
                dados_falecidos = gerador_module.buscar_dados_falecidos(cursor, cnpj)
                if dados_falecidos:
                    self._log(f"  └─ {len(dados_falecidos)} transação(ões) de falecidos encontradas", "success")
                else:
                    self._log("  └─ Nenhuma venda para falecidos encontrada", "info")

                # 5.5 Gerar Relatório(s) Excel
                for tipo in tipos:
                    tipo_nome = "Completo" if tipo == 1 else "Resumido"
                    self._log(f"  └─ Gerando relatório {tipo_nome}...", "info")

                    # Mudar para o diretório de saída temporariamente
                    cwd_original = os.getcwd()
                    os.chdir(diretorio)

                    try:
                        # CHAMADA ATUALIZADA COM TODOS OS PARÂMETROS
                        resultado = gerador_module.gerarRelatorioMovimentacao(
                            cnpj,
                            dados_memoria,
                            tipo,
                            cursor,
                            dados_farmacias,
                            dados_medicamentos,
                            dados_risco,
                            dados_prescritores=dados_prescritores,
                            top20_prescritores=top20_prescritores,
                            id_processamento=id_proc,
                            dados_falecidos=dados_falecidos  # NOVO PARÂMETRO
                        )

                        if resultado == "SEM_VENDAS":
                            self._log(f"  └─ CNPJ sem vendas no período", "warning")
                        else:
                            nome_arquivo = f"{cnpj} ({tipo_nome}).xlsx"
                            self._log(f"  └─ Arquivo gerado: {nome_arquivo}", "success")

                    finally:
                        # Sempre retorna ao diretório original
                        os.chdir(cwd_original)

                sucesso += 1

            except Exception as e:
                self._log(f"  └─ ERRO: {str(e)}", "error")
                traceback.print_exc()  # Imprime erro no console para debug
                erros += 1

        # 6. Finalização e Limpeza
        try:
            cursor.close()
            conn.close()
            self._log("\nConexão com banco de dados encerrada.", "info")
        except:
            pass

        self._atualizar_progresso(total, total)
        self._log_separador("PROCESSAMENTO CONCLUÍDO")
        self._log(f"CNPJs processados com sucesso: {sucesso}", "success")
        if erros > 0:
            self._log(f"CNPJs com erro ou sem dados: {erros}", "warning")

        self._finalizar_processamento(True, diretorio)


    def _finalizar_processamento(self, sucesso, diretorio=None):
        """Finaliza o processamento e restaura interface."""
        self.processando = False
        self.cancelar = False

        # Restaurar botões
        self.btn_cancelar.pack_forget()
        self.btn_gerar.pack(side=tk.LEFT, padx=(0, 10))

        if sucesso and diretorio:
            # Perguntar se deseja abrir a pasta
            resposta = messagebox.askyesno(
                "Processamento Concluído",
                "Relatórios gerados com sucesso!\n\nDeseja abrir a pasta de saída?"
            )
            if resposta:
                try:
                    os.startfile(diretorio)
                except:
                    # Fallback para outros sistemas
                    import subprocess
                    subprocess.run(['explorer', diretorio])


# =============================================================================
# PONTO DE ENTRADA
# =============================================================================
def main():
    # Configura o AppUserModelID para o ícone aparecer corretamente na barra de tarefas
    try:
        import ctypes
        myappid = 'cgu.sentinela.gerador.v3'
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(myappid)
    except Exception:
        pass

    root = tk.Tk()
    app = SentinelaApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
