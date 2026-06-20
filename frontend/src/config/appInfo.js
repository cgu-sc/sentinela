import versionInfo from '../../../version.json';

export const APP_VERSION = versionInfo.version;

export const APP_RUNTIME = {
  WEB: 'Web',
  DESKTOP: 'Desktop',
};

export const getAppRuntimeLabel = () =>
  window.pywebview?.api ? APP_RUNTIME.DESKTOP : APP_RUNTIME.WEB;

export const getAppVersionLabel = () =>
  `${getAppRuntimeLabel()} v${APP_VERSION}`;
