export function buildHealthRegionGeoJson({ ufGeoJson, localidades, uf, regiaoId }) {
  if (!ufGeoJson?.features || !Array.isArray(ufGeoJson.features)) {
    throw new Error('GeoJSON municipal da UF ausente ou invalido.');
  }
  if (!Array.isArray(localidades) || localidades.length === 0) {
    throw new Error('Contrato de localidades indisponivel.');
  }
  if (!uf || !regiaoId) {
    throw new Error('UF e id_regiao_saude sao obrigatorios para montar o territorio.');
  }

  const municipiosDaRegiao = new Set(
    localidades
      .filter((localidade) =>
        localidade.sg_uf === uf
        && String(localidade.id_regiao_saude) === String(regiaoId)
      )
      .map((localidade) => Number(localidade.id_ibge7))
      .filter(Number.isFinite),
  );

  if (municipiosDaRegiao.size === 0) {
    throw new Error('Regiao de saude sem municipios no contrato de localidades.');
  }

  const features = ufGeoJson.features.filter((feature) =>
    municipiosDaRegiao.has(Number(feature.properties?.id)),
  );

  if (features.length === 0) {
    throw new Error('GeoJSON municipal sem geometrias para a regiao de saude.');
  }

  return { type: 'FeatureCollection', features };
}
