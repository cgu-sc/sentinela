



GO
 
-- 1. Autoriza o usuário a entrar na base Santa Catarina
CREATE USER [CGU\dianamv] FOR LOGIN [CGU\dianamv];
GO
 
-- 2. Concede acesso de leitura ao schema
GRANT SELECT ON SCHEMA::fp TO [CGU\dianamv];
GO
 