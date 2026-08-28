-- Section 4.2: catalog item photo uploads, stored on local disk (no cloud
-- storage account exists — see Decisions Log) and quota-tracked per
-- merchant so one merchant can't fill the server's disk.
ALTER TABLE merchants ADD COLUMN storage_used_bytes bigint NOT NULL DEFAULT 0;
