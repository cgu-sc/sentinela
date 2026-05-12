export const formatCpfCnpj = (value) => {
  if (!value) return "—";

  const clean = String(value).replace(/\D/g, "");
  if (clean.length === 11) {
    return clean.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
  }
  if (clean.length === 14) {
    return clean.replace(
      /^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/,
      "$1.$2.$3/$4-$5",
    );
  }

  return value;
};

export const formatSocietyDate = (value) => {
  if (!value) return "—";

  const dateText = String(value).slice(0, 10);
  const match = dateText.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (match) return `${match[3]}/${match[2]}/${match[1]}`;

  return String(value);
};

export const formatCnaeEvidence = (id, description) => {
  const code = id ? String(id) : "Não informado";
  return description ? `${code} - ${description}` : code;
};
