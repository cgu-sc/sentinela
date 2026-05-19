-- ============================================================================
-- BOOTSTRAP CRM: tabelas atuais -> app_*
-- ============================================================================
-- Uso unico para preparar a camada estavel da aplicacao antes de alterar o
-- backend para ler app_*.
--
-- Nao copia dados.
-- Nao cria backup.
-- Se uma app_* ja existir, ela e removida antes do rename.
-- Tabelas opcionais ausentes sao ignoradas.
-- ============================================================================

USE [temp_CGUSC];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '>> [BOOTSTRAP CRM] Renomeando tabelas atuais para app_*...';

BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('fp.crm_concentracao_unico_alertas', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_crm_concentracao_unico_alertas', 'U') IS NOT NULL DROP TABLE fp.app_crm_concentracao_unico_alertas;
        EXEC sp_rename 'fp.crm_concentracao_unico_alertas', 'app_crm_concentracao_unico_alertas';
    END;

    IF OBJECT_ID('fp.crm_concentracao_multiplo_alertas', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_crm_concentracao_multiplo_alertas', 'U') IS NOT NULL DROP TABLE fp.app_crm_concentracao_multiplo_alertas;
        EXEC sp_rename 'fp.crm_concentracao_multiplo_alertas', 'app_crm_concentracao_multiplo_alertas';
    END;

    IF OBJECT_ID('fp.crm_perfil_diario', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_crm_perfil_diario', 'U') IS NOT NULL DROP TABLE fp.app_crm_perfil_diario;
        EXEC sp_rename 'fp.crm_perfil_diario', 'app_crm_perfil_diario';
    END;

    IF OBJECT_ID('fp.crm_perfil_horario', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_crm_perfil_horario', 'U') IS NOT NULL DROP TABLE fp.app_crm_perfil_horario;
        EXEC sp_rename 'fp.crm_perfil_horario', 'app_crm_perfil_horario';
    END;

    IF OBJECT_ID('fp.mediana_autorizacoes_horaria', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_mediana_autorizacoes_horaria', 'U') IS NOT NULL DROP TABLE fp.app_mediana_autorizacoes_horaria;
        EXEC sp_rename 'fp.mediana_autorizacoes_horaria', 'app_mediana_autorizacoes_horaria';
    END;

    IF OBJECT_ID('fp.mediana_autorizacoes_horaria_movel', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_mediana_autorizacoes_horaria_movel', 'U') IS NOT NULL DROP TABLE fp.app_mediana_autorizacoes_horaria_movel;
        EXEC sp_rename 'fp.mediana_autorizacoes_horaria_movel', 'app_mediana_autorizacoes_horaria_movel';
    END;

    IF OBJECT_ID('fp.volume_horario_anomalo_alertas', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_volume_horario_anomalo_alertas', 'U') IS NOT NULL DROP TABLE fp.app_volume_horario_anomalo_alertas;
        EXEC sp_rename 'fp.volume_horario_anomalo_alertas', 'app_volume_horario_anomalo_alertas';
    END;

    IF OBJECT_ID('fp.crm_raiox_tx', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_crm_raiox_tx', 'U') IS NOT NULL DROP TABLE fp.app_crm_raiox_tx;
        EXEC sp_rename 'fp.crm_raiox_tx', 'app_crm_raiox_tx';
    END;

    IF OBJECT_ID('fp.alertas_crm_geografico', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_alertas_crm_geografico', 'U') IS NOT NULL DROP TABLE fp.app_alertas_crm_geografico;
        EXEC sp_rename 'fp.alertas_crm_geografico', 'app_alertas_crm_geografico';
    END;

    IF OBJECT_ID('fp.alertas_crm_registro', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_alertas_crm_registro', 'U') IS NOT NULL DROP TABLE fp.app_alertas_crm_registro;
        EXEC sp_rename 'fp.alertas_crm_registro', 'app_alertas_crm_registro';
    END;

    IF OBJECT_ID('fp.alertas_crm', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_alertas_crm', 'U') IS NOT NULL DROP TABLE fp.app_alertas_crm;
        EXEC sp_rename 'fp.alertas_crm', 'app_alertas_crm';
    END;

    IF OBJECT_ID('fp.crm_export', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_crm_export', 'U') IS NOT NULL DROP TABLE fp.app_crm_export;
        EXEC sp_rename 'fp.crm_export', 'app_crm_export';
    END;

    IF OBJECT_ID('fp.indicador_crm_bench_uf', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_indicador_crm_bench_uf', 'U') IS NOT NULL DROP TABLE fp.app_indicador_crm_bench_uf;
        EXEC sp_rename 'fp.indicador_crm_bench_uf', 'app_indicador_crm_bench_uf';
    END;

    IF OBJECT_ID('fp.indicador_crm_bench_regiao', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_indicador_crm_bench_regiao', 'U') IS NOT NULL DROP TABLE fp.app_indicador_crm_bench_regiao;
        EXEC sp_rename 'fp.indicador_crm_bench_regiao', 'app_indicador_crm_bench_regiao';
    END;

    IF OBJECT_ID('fp.indicador_crm_bench_br', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_indicador_crm_bench_br', 'U') IS NOT NULL DROP TABLE fp.app_indicador_crm_bench_br;
        EXEC sp_rename 'fp.indicador_crm_bench_br', 'app_indicador_crm_bench_br';
    END;

    IF OBJECT_ID('fp.indicador_crm_hhi', 'U') IS NOT NULL
    BEGIN
        IF OBJECT_ID('fp.app_indicador_crm_hhi', 'U') IS NOT NULL DROP TABLE fp.app_indicador_crm_hhi;
        EXEC sp_rename 'fp.indicador_crm_hhi', 'app_indicador_crm_hhi';
    END;

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    THROW;
END CATCH;

PRINT '>> [BOOTSTRAP CRM] Concluido.';
