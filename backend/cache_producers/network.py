def sync_network(cnpj: str, engine=None) -> None:
    from api.services.analytics._cache import sync_network as _sync_network

    _sync_network(cnpj)
