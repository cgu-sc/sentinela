from datetime import date
from typing import Any


def _format_cpf_cnpj(v: str | None) -> str:
    """Formata CPF ou CNPJ com mascara padrao."""
    if not v:
        return "—"
    clean = "".join(filter(str.isdigit, v))
    if len(clean) == 11:
        return f"{clean[:3]}.{clean[3:6]}.{clean[6:9]}-{clean[9:]}"
    if len(clean) == 14:
        return f"{clean[:2]}.{clean[2:5]}.{clean[5:8]}/{clean[8:12]}-{clean[12:]}"
    return v


def _format_decimal_pt(value: float, decimals: int = 2) -> str:
    """Formata numero decimal no padrao brasileiro."""
    return f"{value:,.{decimals}f}".replace(',', 'X').replace('.', ',').replace('X', '.')


def _format_date_pt(value: Any) -> str:
    """Formata datas no padrao brasileiro, preservando vazio como travessao."""
    if not value:
        return "—"
    if hasattr(value, "strftime"):
        return value.strftime("%d/%m/%Y")
    text = str(value)
    if len(text) >= 10 and text[4:5] == "-" and text[7:8] == "-":
        return f"{text[8:10]}/{text[5:7]}/{text[:4]}"
    return text


def _title_case_pt(value: Any) -> str:
    """Aplica capitalizacao simples para nomes vindos em caixa alta."""
    text = str(value or "").strip()
    return text.title() if text else "Não identificado"


def _format_month_year_pt(month_key: str) -> str:
    """Formata uma chave mensal YYYY-MM como MM/YYYY."""
    parts = (month_key or "").split("-")
    if len(parts) != 2:
        return month_key or "—"
    year, month = parts
    if len(year) != 4 or len(month) != 2:
        return month_key or "—"
    return f"{month}/{year}"


def _format_month_year_long_pt(month_key: str) -> str:
    """Formata uma chave mensal YYYY-MM como mes por extenso e ano."""
    month_names = {
        "01": "janeiro",
        "02": "fevereiro",
        "03": "março",
        "04": "abril",
        "05": "maio",
        "06": "junho",
        "07": "julho",
        "08": "agosto",
        "09": "setembro",
        "10": "outubro",
        "11": "novembro",
        "12": "dezembro",
    }
    parts = (month_key or "").split("-")
    if len(parts) != 2:
        return month_key or "—"
    year, month = parts
    month_name = month_names.get(month)
    if len(year) != 4 or month_name is None:
        return month_key or "—"
    return f"{month_name} de {year}"


def _format_date_month_year_long_pt(value: date) -> str:
    """Formata uma data como mes por extenso e ano."""
    return _format_month_year_long_pt(f"{value.year:04d}-{value.month:02d}")


def _format_full_date_long_pt(value: date) -> str:
    """Formata uma data como dia, mes por extenso e ano."""
    return f"{value.day} de {_format_date_month_year_long_pt(value)}"


def _format_semestre_pt(semestre: str) -> str:
    """Formata labels como 1S/2021 para 1o Semestre/2021."""
    label = (semestre or "").strip()
    if len(label) >= 7 and label[0] in {"1", "2"} and label[1].upper() == "S" and label[2] == "/":
        return f"{label[0]}º Semestre/{label[3:]}"
    return label


def _semester_key_from_date(value: date) -> int:
    semestre = 1 if value.month <= 6 else 2
    return value.year * 100 + semestre


def _semester_key_from_label(semestre: str) -> int | None:
    label = (semestre or "").strip()
    if len(label) >= 7 and label[0] in {"1", "2"} and label[1].upper() == "S" and label[2] == "/":
        try:
            return int(label[3:]) * 100 + int(label[0])
        except ValueError:
            return None
    if "-S" in label:
        year, sem = label.split("-S", 1)
        try:
            return int(year) * 100 + int(sem[:1])
        except ValueError:
            return None
    return None


def _semester_distance(start_key: int, end_key: int) -> int:
    start_year, start_sem = divmod(start_key, 100)
    end_year, end_sem = divmod(end_key, 100)
    return (end_year - start_year) * 2 + (end_sem - start_sem)


def _format_list_pt(items: list[str]) -> str:
    """Formata lista em portugues: A, B e C."""
    unique_items = list(dict.fromkeys(item for item in items if item))
    if not unique_items:
        raise RuntimeError("Lista de municipios obrigatoria para comparacao regional da Nota Tecnica.")
    if len(unique_items) == 1:
        return unique_items[0]
    if len(unique_items) == 2:
        return f"{unique_items[0]} e {unique_items[1]}"
    return f"{', '.join(unique_items[:-1])} e {unique_items[-1]}"
