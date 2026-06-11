import { PALETTE, RISK_COLORS } from './colors.js';

export const DEFAULT_TARGET_KEY = 'parkinson_menor_50';

export const TARGET_KPI_CONFIGS = {
  farmacias: {
    icon: 'pi pi-building',
    color: PALETTE.blue[500],
  },
  valor_incompativel: {
    icon: 'pi pi-money-bill',
    color: RISK_COLORS.HIGH,
  },
  cpfs_envolvidos: {
    icon: 'pi pi-users',
    color: PALETTE.violet[500],
  },
  municipios: {
    icon: 'pi pi-map-marker',
    color: PALETTE.emerald[500],
  },
  ufs: {
    icon: 'pi pi-map',
    color: PALETTE.amber[500],
  },
};

export const TARGET_GROUPS = [
  {
    id: 'clinico',
    label: 'Clínico',
    targets: [
      {
        key: 'parkinson_menor_50',
        label: 'Parkinson em menores de 50 anos',
        description: 'Farmácias com dispensações de medicamentos de Parkinson para beneficiários com idade inferior a 50 anos.',
        sourceStatus: 'ready',
        endpoint: 'targetParkinsonMenor50',
        tableComponent: 'ParkinsonTargetTable',
        tableSubtitle: 'Ranking de estabelecimentos com recorte de Parkinson em menores de 50 anos',
        valueHeader: 'Valor dos CPFs < 50 anos',
        mapValueLabel: 'Valor dos CPFs < 50 anos',
        mapScopeLabel: 'Valor dos CPFs abaixo de 50 anos',
        mapMetric: 'valor_incompativel',
        defaultSortField: 'valor_incompativel',
        defaultSortOrder: -1,
        enabled: true,
      },
      {
        key: 'diabetes_menor_20',
        label: 'Diabetes em menores de 20 anos',
        description: 'Farmácias com dispensações de medicamentos de diabetes para beneficiários com idade inferior a 20 anos.',
        sourceStatus: 'ready',
        endpoint: 'targetDiabetesMenor20',
        tableComponent: 'ParkinsonTargetTable',
        tableSubtitle: 'Ranking de estabelecimentos com recorte de diabetes em menores de 20 anos',
        valueHeader: 'Valor dos CPFs < 20 anos',
        mapValueLabel: 'Valor dos CPFs < 20 anos',
        mapScopeLabel: 'Valor dos CPFs abaixo de 20 anos',
        mapMetric: 'valor_incompativel',
        defaultSortField: 'valor_incompativel',
        defaultSortOrder: -1,
        enabled: true,
      },
      {
        key: 'hipertensao_menor_20',
        label: 'Hipertensão em menores de 20 anos',
        description: 'Farmácias com dispensações de medicamentos de hipertensão para beneficiários com idade inferior a 20 anos.',
        sourceStatus: 'ready',
        endpoint: 'targetHipertensaoMenor20',
        tableComponent: 'ParkinsonTargetTable',
        tableSubtitle: 'Ranking de estabelecimentos com recorte de hipertensão em menores de 20 anos',
        valueHeader: 'Valor dos CPFs < 20 anos',
        mapValueLabel: 'Valor dos CPFs < 20 anos',
        mapScopeLabel: 'Valor dos CPFs abaixo de 20 anos',
        mapMetric: 'valor_incompativel',
        defaultSortField: 'valor_incompativel',
        defaultSortOrder: -1,
        enabled: true,
      },
      {
        key: 'osteoporose_homens',
        label: 'Osteoporose em homens',
        description: 'Farmácias com dispensações de medicamentos de osteoporose para beneficiários do sexo masculino.',
        sourceStatus: 'ready',
        endpoint: 'targetOsteoporoseHomens',
        tableComponent: 'ParkinsonTargetTable',
        tableSubtitle: 'Ranking de estabelecimentos com recorte de osteoporose em homens',
        valueHeader: 'Valor incompatível',
        mapValueLabel: 'Valor incompatível',
        mapScopeLabel: 'Valor incompatível',
        mapMetric: 'valor_incompativel',
        defaultSortField: 'valor_incompativel',
        defaultSortOrder: -1,
        enabled: true,
      },
    ],
  },
  {
    id: 'producao',
    label: 'Produção',
    targets: [
      {
        key: 'aumento_atipico_vendas',
        label: 'Aumento atípico de vendas',
        description: 'Recorte de produção ainda não habilitado.',
        enabled: false,
      },
    ],
  },
];
