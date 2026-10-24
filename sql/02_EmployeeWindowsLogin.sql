USE KafeYonetimDB;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

CREATE UNIQUE INDEX UX_Employee_WindowsLogin
ON dbo.Employee (WindowsLogin)
WHERE WindowsLogin IS NOT NULL;
GO

SELECT name, is_unique, filter_definition
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.Employee')
  AND name = N'UX_Employee_WindowsLogin';