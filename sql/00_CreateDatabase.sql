USE master;
GO

IF DB_ID(N'KafeYonetimDB') IS NULL
    EXEC(N'CREATE DATABASE KafeYonetimDB');
GO

USE KafeYonetimDB;
GO

SELECT DB_NAME() AS DatabaseName;