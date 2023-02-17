create table AHOY_TASK
(
  atask_key   INTEGER generated always as identity,
  atask_cmd   CLOB,
  atask_state VARCHAR2(20),
  atask_space VARCHAR2(200),
  atask_start TIMESTAMP(6),
  atask_end   TIMESTAMP(6),
  atask_msg   CLOB,
  atask_job   VARCHAR2(100)
)
partition by hash (ATASK_SPACE);

-- Add comments to the table 
comment on table AHOY_TASK
  is 'Table of tasks for the Ad-hoc yeald processor. The table contains both task definition and the log of execution.';
-- Add comments to the columns 
comment on column AHOY_TASK.atask_key
  is 'Surrogate key, it also influents priority of execution';
comment on column AHOY_TASK.atask_cmd
  is 'SQL command to be executed.';
comment on column AHOY_TASK.atask_state
  is 'State of the task: TBD ... to be done, OK ... finished successfully, ERR ... finished unsuccessfully, RUN ... just running, BAT<nr> ... waiting batches';
comment on column AHOY_TASK.atask_space
  is 'Taskspace of independently running tasks';
comment on column AHOY_TASK.atask_start
  is 'Timestamp of the start of execution';
comment on column AHOY_TASK.atask_end
  is 'Timestamp of the end of execution';
comment on column AHOY_TASK.atask_msg
  is 'Eventual error message';
comment on column AHOY_TASK.atask_job
  is 'Name of the realization Oracle Scheduler Job';
-- Create/Recreate primary, unique and foreign key constraints 
alter table AHOY_TASK
  add primary key (ATASK_KEY)
  using index local;

