USE KafeYonetimDB;
GO

CREATE TABLE dbo.Employee
(
    EmployeeId int IDENTITY(1,1) NOT NULL,
    EmployeeCode nvarchar(20) NOT NULL,
    FullName nvarchar(100) NOT NULL,
    WindowsLogin nvarchar(200) NULL,
    BaseSalary decimal(12,2) NOT NULL DEFAULT (0),
    IsActive bit NOT NULL DEFAULT (1),
    CreatedAt datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedAt datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Employee PRIMARY KEY (EmployeeId),
    CONSTRAINT C_Employee_1 UNIQUE (EmployeeCode),
    CONSTRAINT C_Employee_2 CHECK (BaseSalary >= 0)
);
GO

SELECT * FROM dbo.Employee;