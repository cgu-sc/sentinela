import packageInfo from '../../package.json';

export const APP_VERSION = packageInfo.version;

export const APP_RUNTIME = {
  WEB: 'Web',
  DESKTOP: 'Desktop',
};

export const getAppRuntimeLabel = () =>
  window.pywebview?.api ? APP_RUNTIME.DESKTOP : APP_RUNTIME.WEB;

export const getAppVersionLabel = () =>
  `${getAppRuntimeLabel()} v${APP_VERSION}`;
