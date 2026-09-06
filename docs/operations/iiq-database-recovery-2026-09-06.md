# IIQ database recovery — 2026-09-06

## Incident

IdentityIQ failed its startup probe because SQL Server marked the `identityiq`
database `SUSPECT` after recovery. SQL Server reported that the recovery log did
not contain `LOP_END_CKPT`.

## Recovery performed

1. Created the Longhorn snapshot `pre-iiq-db-repair-20260906` for the MSSQL PVC.
2. Put the database into emergency/single-user mode.
3. Ran `DBCC CHECKDB ([identityiq], REPAIR_ALLOW_DATA_LOSS)`.
4. Returned the database to `MULTI_USER` mode.

`DBCC CHECKDB` completed with zero allocation errors and zero consistency errors.
The database is now `ONLINE`.

## Follow-up

The repair rebuilt the transaction log and broke the previous restore chain.
Keep the Longhorn backup and pre-repair snapshot until the IIQ application has
been validated. Future incidents should prefer restoring the known-good backup
over repeating a data-loss repair.
