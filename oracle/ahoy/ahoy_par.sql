create table AHOY_PAR
(
  apar_space    VARCHAR2(200 CHAR),
  apar_threads  INTEGER,
  apar_last_err CLOB
)
partition by hash (APAR_SPACE);

-- Add comments to the table 
comment on table AHOY_PAR
  is 'Table of parameters for the Ad-hoc yield processor.';
-- Add comments to the columns 
comment on column AHOY_PAR.apar_space
  is 'Taskspace of these parameters.';
comment on column AHOY_PAR.apar_threads
  is 'Maximum number of threads running parallelly.';
comment on column AHOY_PAR.apar_last_err
  is 'Information about possible processor error.';
-- Create/Recreate indexes 
create unique index AHOY_PAR_IDX on AHOY_PAR ('$'||APAR_SPACE, APAR_SPACE) -- to support NULL
  nologging  local;



