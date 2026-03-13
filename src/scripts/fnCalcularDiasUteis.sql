CREATE FUNCTION dbo.fnCalcularDiasUteis
(
    @DataInicio DATE,
    @DataFim DATE
)
RETURNS INT
AS
BEGIN
    DECLARE @DiasUteis INT;

    SET @DiasUteis = 
        (DATEDIFF(DAY, @DataInicio, @DataFim) + 1) 
        - (DATEDIFF(WEEK, @DataInicio, @DataFim) * 2)
        - (CASE WHEN DATEPART(WEEKDAY, @DataInicio) = 1 THEN 1 ELSE 0 END)
        - (CASE WHEN DATEPART(WEEKDAY, @DataFim) = 7 THEN 1 ELSE 0 END);

    RETURN @DiasUteis;
END;