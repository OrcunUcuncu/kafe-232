USE KafeYonetimDB;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.Employee (EmployeeCode, FullName)
    VALUES (N'TEST-MODIFIED', N'Test Çalışanı');

    DECLARE @EmployeeId int = CONVERT(int, SCOPE_IDENTITY());

    SELECT N'ÖNCE' AS Asama, FullName, CreatedAt, ModifiedAt
    FROM dbo.Employee
    WHERE EmployeeId = @EmployeeId;

    WAITFOR DELAY '00:00:01';

    UPDATE dbo.Employee
    SET FullName = N'Güncellenmiş Test Çalışanı'
    WHERE EmployeeId = @EmployeeId;

    SELECT N'SONRA' AS Asama, FullName, CreatedAt, ModifiedAt
    FROM dbo.Employee
    WHERE EmployeeId = @EmployeeId;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;