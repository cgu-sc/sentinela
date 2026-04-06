import { ref } from 'vue';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import { INDICATOR_GROUPS, INDICATOR_THRESHOLDS } from '@/config/riskConfig';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── PrimeIcons codepoints ──────────────────────────────────
const PI = {
  SHIELD:              0xe9b9,
  CHART_LINE:          0xe98b,
  CHART_BAR:           0xe96d,
  TABLE:               0xe969,
  EXCLAMATION_TRIANGLE:0xe922,
  CHECK_CIRCLE:        0xe90a,
  TIMES_CIRCLE:        0xe90c,
  BUILDING:            0xe9cf,
  MONEY_BILL:          0xe974,
  PERCENTAGE:          0xe9be,
  MAP_MARKER:          0xe968,
  USERS:               0xe941,
  FILE_PDF:            0xe98d,
  GLOBE:               0xe94f,
  COMPASS:             0xe9ab,
  SHARE_ALT:           0xe93f,
  MAP:                 0xe9c2,
  SITEMAP:             0xe93e,
};

function formatPopulacao(n) {
  if (n == null) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2).replace('.', ',')} M`;
  if (n >= 1_000)     return `${(n / 1_000).toFixed(1).replace('.', ',')} mil`;
  return n.toLocaleString('pt-BR');
}

async function loadPrimeiconsFontInto(pdf) {
  try {
    const res = await fetch('/fonts/primeicons.ttf');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = await res.arrayBuffer();
    const bytes = new Uint8Array(buf);
    let binary = '';
    // Build binary string in chunks to avoid stack overflow on large fonts
    for (let i = 0; i < bytes.length; i += 8192) {
      binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    }
    const b64 = btoa(binary);
    pdf.addFileToVFS('primeicons.ttf', b64);
    pdf.addFont('primeicons.ttf', 'primeicons', 'normal');
    return true;
  } catch (e) {
    console.warn('[usePdfExport] PrimeIcons not loaded:', e);
    return false;
  }
}

// ── Helpers de cor/risco ───────────────────────────────────
function getRiscoStatus(risco, thresholdKey = 'default') {
  const t = INDICATOR_THRESHOLDS[thresholdKey] ?? INDICATOR_THRESHOLDS.default;
  const r = risco != null ? Math.round(risco * 10) / 10 : null;
  if (r == null)      return { label: 'SEM DADOS', rgb: [150, 150, 150] };
  if (r >= t.critico) return { label: 'CRÍTICO',   rgb: [239, 68,  68]  };
  if (r >= t.atencao) return { label: 'ATENÇÃO',   rgb: [249, 115, 22]  };
  return                     { label: 'NORMAL',    rgb: [16,  185, 129] };
}

function fmtVal(valor, formato, formatCurrencyFull) {
  if (valor == null) return '—';
  if (formato === 'pct')  return valor.toFixed(2) + '%';
  if (formato === 'pct3') return valor.toFixed(3) + '%';
  if (formato === 'val')  return formatCurrencyFull(valor);
  return valor.toFixed(2);
}

function fmtRisco(v) {
  return v != null ? v.toFixed(1) + 'x' : '—';
}

// ── Composable ─────────────────────────────────────────────
export function usePdfExport() {
  const isExporting = ref(false);

  async function exportCnpjPdf({
    cnpjData, geoData, cnpj, qtdMunicipiosRegiao,
    evolutionTabRef, indicatorsTabRef, crmsTabRef,
    cnpjNavStore, formatCurrencyFull, formatNumberFull,
  }) {
    isExporting.value = true;
    const originalTab = cnpjNavStore.activeTabIndex;

    try {
      const pdf = new jsPDF({ orientation: 'p', unit: 'mm', format: 'a4' });
      const pageW = pdf.internal.pageSize.getWidth();
      const margin = 14;
      const contentW = pageW - margin * 2;

      // ── PrimeIcons font ──────────────────────────────────
      const hasPrimeicons = await loadPrimeiconsFontInto(pdf);

      /**
       * Draws a PrimeIcon glyph and returns the horizontal space it occupied
       * (icon width + gap), so callers can offset subsequent text.
       */
      const drawIcon = (codepoint, x, y, { size = 9, color = [255, 255, 255] } = {}) => {
        if (!hasPrimeicons) return 0;
        const prevFont = pdf.getFont();
        const prevSize = pdf.getFontSize();
        pdf.setFont('primeicons', 'normal');
        pdf.setFontSize(size);
        pdf.setTextColor(...color);
        pdf.text(String.fromCodePoint(codepoint), x, y);
        pdf.setFont(prevFont.fontName, prevFont.fontStyle);
        pdf.setFontSize(prevSize);
        return size * 0.38 + 1.5; // approx glyph width + gap
      };

      // ── Helpers visuais ──────────────────────────────────
      const pageHeader = (title, subtitle = '', iconCodepoint = null) => {
        pdf.setFillColor(15, 23, 42);
        pdf.rect(0, 0, pageW, 20, 'F');
        let titleX = margin;
        if (iconCodepoint) {
          titleX += drawIcon(iconCodepoint, margin, 13.5, { size: 10, color: [99, 179, 237] });
        }
        pdf.setFontSize(12);
        pdf.setFont('helvetica', 'bold');
        pdf.setTextColor(255, 255, 255);
        pdf.text(title, titleX, 13);
        if (subtitle) {
          pdf.setFontSize(8);
          pdf.setFont('helvetica', 'normal');
          pdf.setTextColor(180, 180, 180);
          pdf.text(subtitle, pageW - margin, 13, { align: 'right' });
        }
      };

      const sectionTitle = (text, y, color = [30, 41, 59], iconCodepoint = null) => {
        let textX = margin;
        if (iconCodepoint) {
          textX += drawIcon(iconCodepoint, margin, y, { size: 9, color });
        }
        pdf.setFontSize(10);
        pdf.setFont('helvetica', 'bold');
        pdf.setTextColor(...color);
        pdf.text(text, textX, y);
        return y + 7;
      };

      // ── PÁGINA CAPA (Início) ──────────────────────────────────
      const fetchBase64 = async (url) => {
        try {
          const res = await fetch(url);
          if (!res.ok) return null;
          const blob = await res.blob();
          return new Promise(resolve => {
            const rd = new FileReader();
            rd.onload = () => resolve(rd.result);
            rd.readAsDataURL(blob);
          });
        } catch(e) { return null; }
      };

      // Usando Date.now() para invalidar o cache forte do navegador (Cache Busting)
      const cguB64 = await fetchBase64(`/img/logo_cgu.png?v=${Date.now()}`);

      const pageH = pdf.internal.pageSize.getHeight();
      pdf.setFillColor(15, 23, 42); 
      pdf.rect(0, 0, pageW, pageH, 'F');
      
      pdf.setFillColor(99, 102, 241); 
      pdf.rect(0, 0, 4, pageH, 'F');

      let currentCY = 15;

      if (cguB64) {
        // Logo oficial, proporção 750x800 (15:16)
        const sizeW = 110; 
        const sizeH = 117.3;
        pdf.addImage(cguB64, 'PNG', (pageW - sizeW) / 2, currentCY, sizeW, sizeH);
        currentCY += (sizeH + 10);
      } else {
        currentCY += 50; // Fallback caso não carregue
      }
      
      pdf.setFont('helvetica', 'normal');
      pdf.setFontSize(12);
      pdf.setTextColor(148, 163, 184); 
      pdf.text('SISTEMA DE AUDITORIA CONTÍNUA', margin + 8, currentCY);
      
      currentCY += 8;
      pdf.setFont('helvetica', 'bold');
      pdf.setFontSize(28);
      pdf.setTextColor(248, 250, 252); 
      pdf.text('Farmácia Popular', margin + 8, currentCY);
      
      currentCY += 12;
      pdf.setFont('helvetica', 'bold');
      pdf.setFontSize(18);
      pdf.setTextColor(99, 102, 241); 
      pdf.text('Relatório de Conformidade do CNPJ', margin + 8, currentCY);

      currentCY += 40;
      pdf.setFillColor(30, 41, 59); 
      pdf.roundedRect(margin + 8, currentCY, contentW - 16, 42, 3, 3, 'F');
      
      pdf.setFont('helvetica', 'bold');
      pdf.setFontSize(10);
      pdf.setTextColor(248, 250, 252);
      pdf.text(`RAZÃO SOCIAL:`, margin + 14, currentCY + 10);
      
      pdf.setFont('helvetica', 'normal');
      pdf.setFontSize(10);
      const capRazaoLines = pdf.splitTextToSize(cnpjData.razao_social ?? '—', contentW - 30);
      pdf.text(capRazaoLines, margin + 45, currentCY + 10);
      
      pdf.setFont('helvetica', 'bold');
      pdf.text(`CNPJ:`, margin + 14, currentCY + 22);
      pdf.setFont('helvetica', 'normal');
      const cnpjFormatted = cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
      pdf.text(`${cnpjFormatted}`, margin + 45, currentCY + 22);
      
      pdf.setFont('helvetica', 'bold');
      pdf.text(`LOCALIDADE:`, margin + 14, currentCY + 34);
      pdf.setFont('helvetica', 'normal');
      const capLocal = [geoData?.no_municipio, geoData?.sg_uf].filter(Boolean).join(' - ') || cnpjData?.uf;
      pdf.text(capLocal ?? '', margin + 45, currentCY + 34);

      pdf.setFont('helvetica', 'normal');
      pdf.setFontSize(9);
      pdf.setTextColor(100, 116, 139); 
      pdf.text(`Gerado em: ${new Date().toLocaleString('pt-BR')}`, margin + 8, pageH - 20);

      pdf.addPage();

      // ── PÁGINA 2 — Identificação (Subsequente Branco) ──────
      // Cor de risco a partir do % sem comprovação
      const perc = cnpjData.percValSemComp ?? 0;
      const riskRgb = perc >= 30 ? [239, 68,  68]
                    : perc >= 15 ? [249, 115, 22]
                    : perc >= 5  ? [234, 179, 8]
                    :              [16,  185, 129];

      // ── Banner escuro ──────────────────────────────
      const headerH = 54;
      pdf.setFillColor(15, 23, 42);
      pdf.rect(0, 0, pageW, headerH, 'F');

      // Accent line no topo (efeito gradiente parcial)
      pdf.setFillColor(99, 102, 241);
      pdf.rect(0, 0, contentW * 0.45, 2.5, 'F');

      // Branding
      pdf.setFontSize(7.5);
      pdf.setFont('helvetica', 'bold');
      pdf.setTextColor(99, 102, 241);
      pdf.text('SENTINELA · PFPB · CGU', margin, 11);
      pdf.setFontSize(7);
      pdf.setFont('helvetica', 'normal');
      pdf.setTextColor(100, 116, 139);
      pdf.setFontSize(8);
      pdf.text(`Gerado em ${new Date().toLocaleString('pt-BR')}`, pageW - margin, 11, { align: 'right' });

      // Razão social
      const razaoLines = pdf.splitTextToSize(cnpjData.razao_social ?? '—', contentW * 0.78);
      pdf.setFontSize(16);
      pdf.setFont('helvetica', 'bold');
      pdf.setTextColor(255, 255, 255);
      pdf.text(razaoLines.slice(0, 2), margin, 23);

      // CNPJ + localização
      const cnpjFmt = cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
      pdf.setFontSize(8);
      pdf.setFont('helvetica', 'normal');
      pdf.setTextColor(148, 163, 184);
      const locLine = [
        `CNPJ ${cnpjFmt}`,
        geoData?.no_municipio ?? cnpjData?.municipio,
        geoData?.sg_uf ?? cnpjData?.uf,
        geoData?.no_regiao_saude ? `Região de Saúde: ${geoData.no_regiao_saude}` : null,
      ].filter(Boolean).join('  ·  ');
      pdf.text(locLine, margin, 36);

      // Badge de score (canto inferior direito do banner)
      if (cnpjData.score_risco_final != null) {
        const badge1 = `Score ${cnpjData.score_risco_final.toFixed(1)}`;
        const badge2 = cnpjData.classificacao_risco ?? '';
        const bW1 = 26, bW2 = 32, bH = 8, bY = headerH - 13;
        // Score badge
        pdf.setFillColor(...riskRgb);
        pdf.roundedRect(pageW - margin - bW1 - bW2 - 3, bY, bW1, bH, 2, 2, 'F');
        pdf.setFontSize(7.5);
        pdf.setFont('helvetica', 'bold');
        pdf.setTextColor(255, 255, 255);
        pdf.text(badge1, pageW - margin - bW1 - bW2 - 3 + bW1 / 2, bY + 5.2, { align: 'center' });
        // Classificação badge
        pdf.setFillColor(30, 41, 59);
        pdf.roundedRect(pageW - margin - bW2, bY, bW2, bH, 2, 2, 'F');
        pdf.setTextColor(...riskRgb);
        pdf.text(badge2, pageW - margin - bW2 + bW2 / 2, bY + 5.2, { align: 'center' });
      }

      // ── KPI Cards ──────────────────────────────────
      let y = headerH + 10;
      const cardW = (contentW - 8) / 3;
      const cardH = 24;
      const kpiCards = [
        { label: '% SEM COMPROVAÇÃO',    value: `${cnpjData.percValSemComp?.toFixed(2) ?? '—'}%`, accent: riskRgb },
        { label: 'VALOR SEM COMPROVAÇÃO', value: formatCurrencyFull(cnpjData.valSemComp),          accent: [99, 102, 241] },
        { label: 'TOTAL VENDAS',          value: formatCurrencyFull(cnpjData.totalMov),            accent: [71, 85, 105] },
      ];
      kpiCards.forEach((card, i) => {
        const x = margin + i * (cardW + 4);
        pdf.setFillColor(248, 250, 252);
        pdf.roundedRect(x, y, cardW, cardH, 2, 2, 'F');
        pdf.setFillColor(...card.accent);
        pdf.roundedRect(x, y, 2.5, cardH, 1, 1, 'F');
        pdf.setFontSize(8);
        pdf.setFont('helvetica', 'bold');
        pdf.setTextColor(100, 116, 139);
        pdf.text(card.label, x + 6, y + 8);
        pdf.setFontSize(13);
        pdf.setFont('helvetica', 'bold');
        pdf.setTextColor(...(i === 0 ? riskRgb : [15, 23, 42]));
        pdf.text(card.value, x + 6, y + 18);
      });
      y += cardH + 12;

      // ── Rankings ───────────────────────────────────
      pdf.setFontSize(8);
      pdf.setFont('helvetica', 'bold');
      pdf.setTextColor(148, 163, 184);
      pdf.text('RANKINGS DE CRITICIDADE', margin, y);
      pdf.setDrawColor(226, 232, 240);
      pdf.line(margin + 56, y - 1.5, pageW - margin, y - 1.5);
      y += 7;

      const ranks = [
        { label: 'Rank Nacional',  val: cnpjData.rank_nacional,     total: cnpjData.total_nacional,      icon: PI.GLOBE,      iconColor: [253, 224, 71]  },
        { label: 'Rank Estadual',  val: cnpjData.rank_uf,           total: cnpjData.total_uf,            icon: PI.COMPASS,    iconColor: [203, 213, 225] },
        { label: 'Rank Regional',  val: cnpjData.rank_regiao_saude, total: cnpjData.total_regiao_saude,  icon: PI.SHARE_ALT,  iconColor: [251, 191, 36]  },
        { label: 'Rank Municipal', val: cnpjData.rank_municipio,    total: cnpjData.total_municipio,     icon: PI.BUILDING,   iconColor: [148, 163, 184] },
      ];
      const rankColW = contentW / 4;
      ranks.forEach((r, i) => {
        const x = margin + i * rankColW;
        drawIcon(r.icon, x, y + 7, { size: 13, color: r.iconColor });
        const tx = x + 8;
        pdf.setFontSize(8); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(148, 163, 184);
        pdf.text(r.label, tx, y);
        // Rank value (grande) + total (pequeno) na mesma linha
        const rankStr = r.val != null ? `${r.val}º` : '—';
        pdf.setFontSize(13); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(15, 23, 42);
        pdf.text(rankStr, tx, y + 9);
        const rankW = pdf.getTextWidth(rankStr);
        pdf.setFontSize(8); pdf.setFont('helvetica', 'normal'); pdf.setTextColor(148, 163, 184);
        pdf.text(`/ ${r.total ?? '—'}`, tx + rankW + 1.5, y + 9);
      });
      y += 22;

      // ── Stats contextuais ──────────────────────────
      const ctxStats = [
        { label: 'Municípios da Região', val: qtdMunicipiosRegiao ?? '—',               icon: PI.MAP,      iconColor: [52, 211, 153]  },
        { label: 'Estab. Região',        val: cnpjData.total_regiao_saude ?? '—',        icon: PI.SITEMAP,  iconColor: [148, 163, 184] },
        { label: 'Estab. Município',     val: cnpjData.total_municipio ?? '—',           icon: PI.BUILDING, iconColor: [167, 139, 250] },
        { label: 'Pop. Município',       val: formatPopulacao(geoData?.nu_populacao),    icon: PI.USERS,    iconColor: [96, 165, 250]  },
      ];
      ctxStats.forEach((s, i) => {
        const x = margin + i * rankColW;
        drawIcon(s.icon, x, y + 7, { size: 13, color: s.iconColor });
        const tx = x + 8;
        pdf.setFontSize(8); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(148, 163, 184);
        pdf.text(s.label, tx, y);
        pdf.setFontSize(12); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(15, 23, 42);
        pdf.text(String(s.val), tx, y + 9);
      });
      y += 20;

      // ── Score consolidado ──────────────────────────
      if (cnpjData.score_risco_final != null) {
        const scoreCardH = 20;
        pdf.setFillColor(248, 250, 252);
        pdf.roundedRect(margin, y, contentW, scoreCardH, 2, 2, 'F');
        pdf.setFillColor(...riskRgb);
        pdf.roundedRect(margin, y, 2.5, scoreCardH, 1, 1, 'F');
        pdf.setFontSize(8); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(100, 116, 139);
        pdf.text('SCORE DE RISCO CONSOLIDADO', margin + 6, y + 7);
        pdf.text('CLASSIFICAÇÃO', margin + 70, y + 7);
        pdf.setFontSize(17); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(...riskRgb);
        pdf.text(cnpjData.score_risco_final.toFixed(1), margin + 6, y + 16);
        pdf.setFontSize(12); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(15, 23, 42);
        pdf.text(cnpjData.classificacao_risco ?? '—', margin + 70, y + 16);
      }

      // ── PÁGINA 2 — Evolução Financeira ───────────────────
      cnpjNavStore.activeTabIndex = 1;
      await sleep(900);

      pdf.addPage();
      pageHeader('Evolução Financeira', cnpjData.razao_social, PI.CHART_LINE);

      const semestres = evolutionTabRef.value?.getSemestresData() ?? [];
      const chartImg  = evolutionTabRef.value?.getChartImage(4) ?? null;

      let y2 = 26;

      // Gráfico em alta resolução
      if (chartImg) {
        const chartH = 70;
        pdf.addImage(chartImg, 'JPEG', margin, y2, contentW, chartH);
        y2 += chartH + 6;
      }

      y2 += 5;
      y2 = sectionTitle('DETALHAMENTO SEMESTRAL', y2, [30, 41, 59], PI.TABLE);

      const semRows = semestres.map((s, i) => {
        let tendencia = '-';
        if (i > 0) {
          const diff = s.pct_irregular - semestres[i - 1].pct_irregular;
          tendencia = diff > 0 ? `+${diff.toFixed(1)}pp` : diff < 0 ? `-${Math.abs(diff).toFixed(1)}pp` : `0.0pp`;
        }
        return [
          s.semestre,
          formatCurrencyFull(s.total),
          formatCurrencyFull(s.regular),
          formatCurrencyFull(s.irregular),
          s.pct_irregular.toFixed(1) + '%',
          tendencia,
        ];
      });

      const totalReg = semestres.reduce((a, s) => a + s.regular, 0);
      const totalIrr = semestres.reduce((a, s) => a + s.irregular, 0);
      const totalAll = semestres.reduce((a, s) => a + s.total, 0);

      autoTable(pdf, {
        startY: y2 + 2,
        head: [['Semestre', 'Total Movimentado', 'Total Regular', 'Sem Comprovação', '% S/ Comp', 'Tendência']],
        body: semRows,
        foot: [['TOTAL', formatCurrencyFull(totalAll), formatCurrencyFull(totalReg), formatCurrencyFull(totalIrr), '', '']],
        margin: { left: margin, right: margin },
        styles: { fontSize: 8, cellPadding: 3, font: 'helvetica' },
        headStyles: { fillColor: [15, 23, 42], textColor: 255, fontStyle: 'bold', fontSize: 7.5 },
        footStyles: { fillColor: [240, 240, 240], textColor: [30, 30, 30], fontStyle: 'bold' },
        alternateRowStyles: { fillColor: [249, 250, 251] },
        columnStyles: {
          0: { fontStyle: 'bold' },
          1: { halign: 'right' },
          2: { halign: 'right', textColor: [16, 185, 129] },
          3: { halign: 'right', textColor: [239, 68, 68] },
          4: { halign: 'center', fontStyle: 'bold' },
          5: { halign: 'center' },
        },
        didParseCell: (data) => {
          if (data.section === 'head' || data.section === 'foot') {
            const hAligns = ['left', 'right', 'right', 'right', 'center', 'center'];
            data.cell.styles.halign = hAligns[data.column.index];
          }
          if (data.section === 'body' && data.column.index === 5) {
            const v = data.cell.raw;
            if (v?.startsWith('+')) data.cell.styles.textColor = [239, 68, 68];
            else if (v?.startsWith('-')) data.cell.styles.textColor = [16, 185, 129];
            else data.cell.styles.textColor = [150, 150, 150];
          }
          if (data.section === 'body' && data.column.index === 4) {
            const pct = parseFloat(data.cell.raw);
            if (pct > 5) data.cell.styles.textColor = [239, 68, 68];
            else         data.cell.styles.textColor = [30, 41, 59];
          }
        },
      });

      // ── PÁGINA 3 — Indicadores ────────────────────────────
      cnpjNavStore.activeTabIndex = 2;
      await sleep(500);

      const indicadores    = indicatorsTabRef.value?.getIndicadoresData() ?? {};
      const pontosCriticos = indicatorsTabRef.value?.getPontosCriticos() ?? [];

      pdf.addPage();
      pageHeader('Indicadores de Risco', cnpjData.razao_social, PI.SHIELD);

      let y3 = 26;

      // Resumo para Auditoria
      if (pontosCriticos.length) {
        y3 += 5;
        y3 = sectionTitle(`RESUMO PARA AUDITORIA — ${pontosCriticos.length} INDICADOR(ES) CRITICO(S)`, y3, [185, 28, 28], PI.EXCLAMATION_TRIANGLE);

        autoTable(pdf, {
          startY: y3 + 2,
          head: [['Indicador', 'Risco Regional', 'Valor Farmácia', 'Mediana Regional']],
          body: pontosCriticos.map((p) => [
            p.label,
            p.riscoReg.toFixed(1) + 'x acima',
            fmtVal(p.valor, p.formato, formatCurrencyFull),
            fmtVal(p.medReg, p.formato, formatCurrencyFull),
          ]),
          margin: { left: margin, right: margin },
          styles: { fontSize: 8, cellPadding: 3 },
          headStyles: { fillColor: [127, 29, 29], textColor: 255, fontStyle: 'bold', fontSize: 7.5 },
          styles: { fontSize: 8, cellPadding: 3, fillColor: [255, 245, 245] },
          alternateRowStyles: { fillColor: [255, 245, 245] },
          columnStyles: {
            1: { halign: 'center', textColor: [239, 68, 68], fontStyle: 'bold' },
            2: { halign: 'right' },
            3: { halign: 'right', textColor: [100, 100, 100] },
          },
          didParseCell: (data) => {
            if (data.section === 'head') {
              const hAligns = ['left', 'center', 'right', 'right'];
              data.cell.styles.halign = hAligns[data.column.index];
            }
          },
        });

        y3 = pdf.lastAutoTable.finalY + 8;
      }

      y3 += 5;
      y3 = sectionTitle('INDICADORES DE RISCO POR GRUPO', y3, [30, 41, 59], PI.CHART_BAR);

      const indRows = [];
      for (const grupo of INDICATOR_GROUPS) {
        // Linha de cabeçalho do grupo
        indRows.push([{ content: grupo.label, colSpan: 9, styles: { fontStyle: 'bold', fillColor: [241, 245, 249], textColor: [30, 41, 59], fontSize: 7.5 } }]);
        for (const ind of grupo.indicators) {
          const d = indicadores[ind.key];
          if (!d || d.valor == null) {
            indRows.push([ind.label, { content: 'SEM DADOS', colSpan: 8, styles: { halign: 'center', textColor: [150, 150, 150] } }]);
            continue;
          }
          const status = getRiscoStatus(d.risco_reg, ind.thresholdKey);
          indRows.push([
            ind.label,
            fmtVal(d.valor,   ind.formato, formatCurrencyFull),
            fmtVal(d.med_reg, ind.formato, formatCurrencyFull),
            fmtVal(d.med_uf,  ind.formato, formatCurrencyFull),
            fmtVal(d.med_br,  ind.formato, formatCurrencyFull),
            fmtRisco(d.risco_reg),
            fmtRisco(d.risco_uf),
            fmtRisco(d.risco_br),
            status.label,
          ]);
        }
      }

      autoTable(pdf, {
        startY: y3 + 2,
        head: [['Indicador', 'Farmácia', 'Mediana\nRegião', 'Mediana\nUF', 'Mediana\nBR', 'Risco\nRegião', 'Risco\nUF', 'Risco\nBR', 'Status']],
        body: indRows,
        margin: { left: margin, right: margin },
        styles: { fontSize: 7.5, cellPadding: 2.5, overflow: 'linebreak' },
        headStyles: { fillColor: [30, 41, 59], textColor: 255, fontStyle: 'bold', fontSize: 7 },
        alternateRowStyles: { fillColor: [255, 255, 255] },
        columnStyles: {
          0: { cellWidth: 48 },
          1: { halign: 'right', fontStyle: 'bold' },
          2: { halign: 'right' },
          3: { halign: 'right', textColor: [120, 120, 120] },
          4: { halign: 'right', textColor: [120, 120, 120] },
          5: { halign: 'center', fontStyle: 'bold' },
          6: { halign: 'center', textColor: [120, 120, 120] },
          7: { halign: 'center', textColor: [120, 120, 120] },
          8: { halign: 'center', fontStyle: 'bold' },
        },
        didParseCell: (data) => {
          if (data.section === 'head') {
            const hAligns = ['left', 'right', 'right', 'right', 'right', 'center', 'center', 'center', 'center'];
            data.cell.styles.halign = hAligns[data.column.index];
          }
          if (data.section !== 'body' || data.column.index < 5) return;
          // Colorir colunas de risco e status
          const raw = data.cell.raw;
          if (typeof raw !== 'string') return;
          const risco = parseFloat(raw);
          if (!isNaN(risco)) {
            if (risco >= 3)      data.cell.styles.textColor = [239, 68,  68];
            else if (risco >= 2) data.cell.styles.textColor = [249, 115, 22];
          } else {
            if (raw === 'CRÍTICO')   { data.cell.styles.textColor = [239, 68, 68];  data.cell.styles.fillColor = [255, 240, 240]; }
            else if (raw === 'ATENÇÃO')  { data.cell.styles.textColor = [180, 83,  9]; data.cell.styles.fillColor = [255, 250, 235]; }
            else if (raw === 'NORMAL')   { data.cell.styles.textColor = [5,  150, 105]; }
          }
        },
      });

      // ── PÁGINA 4 — Prescritores ────────────────────────────
      if (crmsTabRef?.value) {
        cnpjNavStore.activeTabIndex = 3;
        await sleep(500);

        const summary = crmsTabRef.value.getSummary() || {};
        const top20 = crmsTabRef.value.getTop20() || [];
        const kpis = crmsTabRef.value.getKpis?.() || {};

        if (top20.length > 0) {
          pdf.addPage();
          pageHeader('Análise de CRMs e Prescritores', cnpjData.razao_social, PI.USERS);

          let y4 = 26;

          // KPI Cards
          const red = [239, 68, 68], orange = [249, 115, 22], yellow = [234, 179, 8], green = [16, 185, 129];
          const crmCards = [
            { label: 'CONCENTRAÇÃO TOP 1', val: fmtVal(kpis.concentracaoTop1, 'pct', formatCurrencyFull), color: kpis.concentracaoTop1 > 40 ? red : kpis.concentracaoTop1 > 20 ? orange : green },
            { label: 'CONCENTRAÇÃO TOP 5', val: fmtVal(kpis.concentracaoTop5, 'pct', formatCurrencyFull), color: kpis.concentracaoTop5 > 70 ? red : kpis.concentracaoTop5 > 50 ? orange : green },
            { label: 'LANÇ. EM SEQUÊNCIA', val: String(kpis.qtdLancamentosAgrupados || 0), color: kpis.qtdLancamentosAgrupados > 0 ? red : green },
            { label: '>30 PRESC/DIA CNPJ', val: String(kpis.qtdPrescrIntensivaLocal || 0), color: kpis.qtdPrescrIntensivaLocal > 0 ? orange : green },
            { label: '>30 PRESC/DIA BRASIL', val: String(kpis.qtdPrescrIntensivaOcultos || 0), color: kpis.qtdPrescrIntensivaOcultos > 0 ? orange : green },
            { label: 'MULTI-FARMÁCIA', val: String(kpis.qtdMultiFarmacia || 0), color: kpis.qtdMultiFarmacia > 0 ? orange : green },
            { label: 'FRAUDES CRM', val: String(kpis.totalIrregularesCfm || 0), color: kpis.totalIrregularesCfm > 0 ? red : green },
            { label: 'DISTÂNCIA (>400KM)', val: String(kpis.qtdAcima400km || 0), color: kpis.qtdAcima400km > 0 ? yellow : green },
          ];

          const cW = (contentW - 9) / 4;
          const cH = 15;
          crmCards.forEach((c, i) => {
            const row = Math.floor(i / 4);
            const col = i % 4;
            const x = margin + col * (cW + 3);
            const cy = y4 + row * (cH + 3);

            pdf.setFillColor(248, 250, 252);
            pdf.roundedRect(x, cy, cW, cH, 2, 2, 'F');
            pdf.setFillColor(...c.color);
            pdf.roundedRect(x, cy, 2, cH, 1, 1, 'F');
            pdf.setFontSize(5.8); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(100, 116, 139);
            pdf.text(c.label, x + 4, cy + 5.5);
            pdf.setFontSize(10); pdf.setFont('helvetica', 'bold'); pdf.setTextColor(...c.color);
            pdf.text(c.val, x + 4, cy + 12);
          });

          y4 += (cH * 2 + 20);
          y4 = sectionTitle('CRMs DE INTERESSE - DETALHAMENTO', y4, [30, 41, 59], PI.TABLE);

          const crmRows = top20.map(m => {
            const issues = [];
            if (m.flag_robo > 0) issues.push('>30 presc/dia local');
            if (m.flag_robo_oculto > 0 && !m.flag_robo) issues.push('>30 presc/dia Brasil');
            if (m.alerta2_tempo_concentrado || m.alerta2) issues.push('Lançamentos sequenciais');
            if (m.flag_crm_invalido > 0) issues.push('CRM Inexistente');
            if (m.flag_prescricao_antes_registro > 0) issues.push('CRM Irregular (Venda anterior ao Registro)');
            if (m.qtd_estabelecimentos_atua === 1) issues.push('Exclusivo do CNPJ');
            if (m.alerta5_geografico) issues.push('Distância >400km');

            let alertStr = issues.length > 0 ? issues.join(' | ') : 'Regular';
            return [
              m.id_medico,
              alertStr,
              formatCurrencyFull(m.vl_total_prescricoes),
              m.nu_prescricoes,
              fmtVal(m.pct_participacao, 'pct', formatCurrencyFull),
              formatNumberFull(m.nu_prescricoes_dia),
              m.qtd_estabelecimentos_atua
            ];
          });

          autoTable(pdf, {
            startY: y4 + 2,
            head: [['CRM', 'Alertas / Status de Auditoria', 'Volume (R$)', 'Prescrições', '% Volume', 'Presc/Dia\nAqui', 'Nº\nFarmácias']],
            body: crmRows,
            margin: { left: margin, right: margin },
            styles: { fontSize: 7, cellPadding: 3, overflow: 'linebreak' },
            headStyles: { fillColor: [30, 41, 59], textColor: 255, fontStyle: 'bold', fontSize: 7.5 },
            alternateRowStyles: { fillColor: [249, 250, 251] },
            columnStyles: {
              0: { fontStyle: 'bold', cellWidth: 24 },
              1: { cellWidth: 56 },
              2: { halign: 'right', fontStyle: 'bold', textColor: [99, 102, 241] },
              3: { halign: 'right' },
              4: { halign: 'center', fontStyle: 'bold' },
              5: { halign: 'center', fontStyle: 'bold' },
              6: { halign: 'center' }
            },
            didParseCell: (data) => {
              if (data.section === 'head') {
                const hAligns = ['left', 'left', 'right', 'right', 'center', 'center', 'center'];
                data.cell.styles.halign = hAligns[data.column.index];
              }
              if (data.section === 'body') {
                if (data.column.index === 1 && data.cell.raw !== 'Regular') {
                  data.cell.styles.textColor = [239, 68, 68];
                  data.cell.styles.fontStyle = 'bold';
                }
                if (data.column.index === 1 && data.cell.raw === 'Regular') {
                  data.cell.styles.textColor = [150, 150, 150];
                }
              }
            }
          });
        }
      }

      // ── Salvar ────────────────────────────────────────────
      const safeName = (cnpjData.razao_social ?? cnpj).replace(/[^a-zA-Z0-9]/g, '_').slice(0, 30);
      pdf.save(`Sentinela_${safeName}_${new Date().toISOString().slice(0, 10)}.pdf`);

    } finally {
      cnpjNavStore.activeTabIndex = originalTab;
      isExporting.value = false;
    }
  }

  return { isExporting, exportCnpjPdf };
}
