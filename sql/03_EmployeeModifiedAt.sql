USE KafeYonetimDB;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TRIGGER dbo.TR_Employee_Modified
ON dbo.Employee
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF TRIGGER_NESTLEVEL() > 1
        RETURN;

    UPDATE e
    SET ModifiedAt = SYSUTCDATETIME()
    FROM dbo.Employee AS e
    INNER JOIN inserted AS i
        ON e.EmployeeId = i.EmployeeId;
END;
GO

SELECT name, is_disabled
FROM sys.triggers
WHERE parent_id = OBJECT_ID(N'dbo.Employee')
  AND name = N'TR_Employee_Modified';